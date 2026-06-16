//
//  ScanView.swift
//  ClamGUI
//
//  UI for scanning a single file
//

import SwiftUI
import UniformTypeIdentifiers

struct ScanView: View {
    @EnvironmentObject var clamAVManager: ClamAVManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var selectedFileURL: URL?
    @State private var isDragging = false
    @State private var manualScanResult: ClamAVManager.ScanResult?
    @State private var isManualScanning = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScanHeaderImage()

                // Header
                Text("Scan a Single File")
                    .font(.title)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Drop zone / File selector
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: [10])
                        )
                        .foregroundColor(
                            isDragging ? .accentColor :
                            isManualScanning ? .secondary.opacity(0.3) : .gray.opacity(0.5)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    isDragging ? Color.accentColor.opacity(0.1) :
                                    isManualScanning ? Color.gray.opacity(0.02) : Color.gray.opacity(0.05)
                                )
                        )

                    VStack(spacing: 15) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 50))
                            .foregroundColor(isManualScanning ? .secondary.opacity(0.3) : .accentColor)

                        Text(isManualScanning ? "Scan in progress..." : "Drag and drop a file here")
                            .font(.headline)

                        if !isManualScanning {
                            Text("or")
                                .foregroundColor(.secondary)

                            Button("Choose File...") {
                                selectFile()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(40)
                }
                .frame(maxWidth: .infinity)
                .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                    handleDrop(providers: providers)
                    return true
                }
                .disabled(isManualScanning)

                // Selected file info
                if let url = selectedFileURL {
                    ScanFileStatusCard(url: url, result: manualScanResult)
                }

                Spacer()

                // Scan button and progress
                VStack(spacing: 15) {
                    if isManualScanning {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .frame(maxWidth: .infinity)

                        Text("Scanning...")
                            .foregroundColor(.secondary)

                        if !clamAVManager.currentScanProgressMessage.isEmpty {
                            Text(clamAVManager.currentScanProgressMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    } else {
                        Button(action: {
                            Task {
                                await scanSelectedFile()
                            }
                        }) {
                            HStack {
                                if isManualScanning {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "play.fill")
                                }
                                Text(isManualScanning ? "Scanning..." : "Scan File")
                            }
                            .frame(minWidth: 150)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedFileURL == nil || !clamAVManager.isScannerReady || isManualScanning)
                    }
                }

                // Scan result
                if let result = manualScanResult, result.status != .error {
                    ScanResultCard(result: result)
                }
            }
            .padding()
            .frame(maxWidth: 700)
        }
    }
    
    // MARK: - File Selection

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select a file to scan"
        panel.allowedContentTypes = [.item]  // Allow any file type

        // Use runModal instead of async begin to avoid deferral warnings
        let response = panel.runModal()
        
        if response == .OK {
            selectedFileURL = panel.url
            // Clear previous scan result when new file is selected
            manualScanResult = nil
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                Task { @MainActor in
                    selectedFileURL = url
                    // Clear previous scan result when new file is selected
                    manualScanResult = nil
                }
            }
        }
    }
    
    private func scanSelectedFile() async {
        guard let url = selectedFileURL, !isManualScanning else { return }

        isManualScanning = true
        defer { isManualScanning = false }

        let result = await clamAVManager.scanFile(at: url.path)
        manualScanResult = result

        // Record in database ONLY if scan was successful (not an error)
        if result.status != .error {
            await recordScanResult(url: url, result: result)
        }

        // Handle infected files
        if case .infected = result.status {
            // Show notification
            if settingsManager.showNotifications {
                NotificationManager.shared.showThreatNotification(
                    fileName: url.lastPathComponent,
                    threatName: result.threatName ?? "Unknown"
                )
                MenuBarManager.shared.notifyThreatFound()
            }

            // Quarantine if enabled
            if settingsManager.quarantineEnabled {
                await quarantineInfectedFile(at: url, threatName: result.threatName ?? "Unknown")
            }
        } else if case .clean = result.status {
            if settingsManager.showNotifications {
                NotificationManager.shared.showScanCompleteNotification(
                    fileName: url.lastPathComponent,
                    isClean: true
                )
            }
        }
    }
    
    /// Record scan result in database
    private func recordScanResult(url: URL, result: ClamAVManager.ScanResult) async {
        let folderId: Int64 = 1
        let status: ScanStatus = result.status == .clean ? .clean : (result.status == .infected ? .infected : .error)
        await ScanResultsDatabase.shared.recordScan(
            path: url.path,
            folderId: folderId,
            status: status,
            threatName: result.threatName
        )
    }

    private func quarantineInfectedFile(at url: URL, threatName: String) async {
        let capability = ScanPathValidator.actionCapability(
            forFileAt: url.path,
            quarantineDirectory: settingsManager.quarantinePath
        )
        guard capability.canQuarantine else {
            return
        }

        let success = await QuarantineManager.shared.quarantineFile(at: url.path, threatName: threatName)

        if success && settingsManager.showNotifications {
            NotificationManager.shared.showWatchdogNotification(
                fileName: url.lastPathComponent,
                status: "Moved to quarantine"
            )
        }
    }

}

// MARK: - Subviews

struct ScanHeaderImage: View {
    private let image = Bundle.main
        .url(forResource: "header", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 506, maxHeight: 135)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
    }
}

struct FileInfoCard: View {
    let url: URL
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "doc.fill")
                .font(.system(size: 30))
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(url.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    Text(formatFileSize(size))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func formatFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

struct ScanFileStatusCard: View {
    let url: URL
    let result: ClamAVManager.ScanResult?

    var body: some View {
        if let result, result.status == .error {
            ScanErrorCard(result: result)
        } else {
            FileInfoCard(url: url)
        }
    }
}

struct ScanErrorCard: View {
    let result: ClamAVManager.ScanResult

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 30))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Scan Error")
                    .font(.headline)
                    .foregroundColor(.orange)

                Text(result.threatName ?? "The file could not be scanned.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(result.filePath)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ScanResultCard: View {
    let result: ClamAVManager.ScanResult
    @EnvironmentObject var settingsManager: SettingsManager

    private var actionCapability: ScanPathValidator.FileActionCapability {
        ScanPathValidator.actionCapability(
            forFileAt: result.filePath,
            quarantineDirectory: settingsManager.quarantinePath
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 15) {
                statusIcon
                    .font(.system(size: 30))

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.headline)
                        .foregroundColor(statusColor)

                    if let threat = result.threatName {
                        Text(threat)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(result.timestamp.formatted())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Threat actions
            if case .infected = result.status {
                Divider()

                HStack(spacing: 10) {
                    Text("Actions:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    if settingsManager.quarantineEnabled && actionCapability.canQuarantine {
                        Button("Quarantine") {
                            quarantineFile()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }

                    Button("Open in Finder") {
                        openInFinder()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }

                if let reason = actionCapability.reason {
                    Label(reason, systemImage: "lock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusBackgroundColor)
        .cornerRadius(8)
    }

    private func quarantineFile() {
        Task {
            await QuarantineManager.shared.quarantineFile(
                at: result.filePath,
                threatName: result.threatName ?? "Unknown"
            )
        }
    }

    private func openInFinder() {
        NSWorkspace.shared.selectFile(result.filePath, inFileViewerRootedAtPath: "")
    }

    private var statusColor: Color {
        switch result.status {
        case .clean:
            return .green
        case .infected:
            return .red
        case .error:
            return .orange
        }
    }

    private var statusBackgroundColor: Color {
        switch result.status {
        case .clean:
            return Color.green.opacity(0.1)
        case .infected:
            return Color.red.opacity(0.1)
        case .error:
            return Color.orange.opacity(0.1)
        }
    }

    private var statusIcon: Image {
        switch result.status {
        case .clean:
            return Image(systemName: "checkmark.circle.fill")
        case .infected:
            return Image(systemName: "exclamationmark.triangle.fill")
        case .error:
            return Image(systemName: "xmark.circle.fill")
        }
    }

    private var statusTitle: String {
        switch result.status {
        case .clean:
            return "Clean"
        case .infected:
            return "Threat Detected"
        case .error:
            return "Scan Error"
        }
    }
}

#Preview {
    ScanView()
        .environmentObject(ClamAVManager.shared)
        .environmentObject(SettingsManager.shared)
}
