//
//  FoundThreatsView.swift
//  ClamGUI
//
//  Displays list of found threats with actions
//

import SwiftUI

struct FoundThreatsView: View {
    @ObservedObject var handler = ThreatActionHandler.shared
    @State private var threats: [ThreatRecord] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 15) {
            // Header
            HStack {
                Text("Found Threats")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if !threats.isEmpty {
                    Text("\(threats.count) threat\(threats.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if threats.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 50))
                        .foregroundColor(.green)

                    Text("No threats found")
                        .font(.headline)

                    Text("All scanned files are clean")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(threats) { threat in
                            ThreatCard(threat: threat, onActionCompleted: loadThreats, onDeleteRecord: deleteThreatRecord)
                        }
                    }
                    .padding()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadThreats()
        }
    }

    private func loadThreats() {
        Task {
            let folderId: Int64 = 1
            let records = ScanResultsDatabase.shared.getInfectedFiles(folderId: folderId)
            await MainActor.run {
                threats = records.map { ThreatRecord(from: $0) }
                isLoading = false
            }
        }
    }
    
    private func deleteThreatRecord(id: Int64) {
        Task {
            let folderId: Int64 = 1
            if let record = threats.first(where: { $0.databaseId == id }) {
                await ScanResultsDatabase.shared.removeRecord(path: record.filePath, folderId: folderId)
            }
            loadThreats()
        }
    }
}

/// Record of a found threat
struct ThreatRecord: Identifiable {
    let id: UUID
    let databaseId: Int64
    let filePath: String
    let threatName: String
    let detectedAt: Date

    init(from record: ScanResultRecord) {
        self.databaseId = record.id
        self.id = UUID()
        self.filePath = record.path
        self.threatName = record.threatName ?? "Unknown"
        self.detectedAt = record.scanTimestamp
    }

    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    var folderPath: String {
        URL(fileURLWithPath: filePath).deletingLastPathComponent().path
    }
}

/// Individual threat card
struct ThreatCard: View {
    let threat: ThreatRecord
    let onActionCompleted: () -> Void
    let onDeleteRecord: (Int64) -> Void
    
    @State private var isQuarantining = false
    @State private var quarantineProgress: Double = 0
    @State private var showingCrossVolumeWarning = false
    @State private var showingNetworkWarning = false
    @State private var showingRemoveRecordConfirm = false
    @State private var showingDeleteFileConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Threat info
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.red)

                VStack(alignment: .leading, spacing: 4) {
                    Text(threat.fileName)
                        .font(.headline)
                        .lineLimit(1)

                    Text(threat.threatName)
                        .font(.caption)
                        .foregroundColor(.red)

                    Text(threat.filePath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(threat.detectedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Action buttons
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if isQuarantining {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Quarantining...")
                                .font(.caption)
                            ProgressView(value: quarantineProgress)
                                .progressViewStyle(.linear)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Button(action: quarantineFile) {
                            Label("Quarantine", systemImage: "lock.shield")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(isQuarantining)
                    }

                    // Open in Finder
                    if !isQuarantining {
                        Button(action: openInFinder) {
                            Label("Show in Finder", systemImage: "folder")
                                .font(.caption)
                        }
                    }

                    Spacer()
                }
                
                // Second row: record/file management actions
                HStack(spacing: 8) {
                    Button(action: removeThreatRecord) {
                        Label("Remove from List", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray.opacity(0.5))
                    .help("Remove this detection from Found Threats without changing the file")

                    Button(role: .destructive, action: confirmDeleteFile) {
                        Label("Delete File", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .help("Permanently delete the file from disk")
                    
                    Spacer()
                }
            }
            .alert("Network Drive Detected", isPresented: $showingNetworkWarning) {
                Button("Delete File Instead", role: .destructive) {
                    Task { await deleteFileFromDisk() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This file is located on a network drive and cannot be quarantined. You can either delete it permanently or leave it in place.")
            }
            .alert("Cross-Volume Quarantine", isPresented: $showingCrossVolumeWarning) {
                Button("Proceed with Quarantine") {
                    Task { await performQuarantine() }
                }
                Button("Delete File Instead", role: .destructive) {
                    Task { await deleteFileFromDisk() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let size = getFileSize(at: URL(fileURLWithPath: threat.filePath)) {
                    Text("This file is on a different drive than your quarantine folder. Quarantining will temporarily use an additional **\(formatFileSize(size))** on your system drive during the copy process.")
                } else {
                    Text("This file is on a different drive than your quarantine folder.")
                }
            }
            .alert("Remove from List", isPresented: $showingRemoveRecordConfirm) {
                Button("Remove") {
                    Task { await removeRecordOnly() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the detection from ClamGUI's Found Threats list. The file will not be changed.")
            }
            .alert("Delete File", isPresented: $showingDeleteFileConfirm) {
                Button("Delete File", role: .destructive) {
                    Task { await deleteFileFromDisk() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the file from disk and removes it from Found Threats.")
            }
        }
        .padding()
        .background(Color.red.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }

    private func removeThreatRecord() {
        showingRemoveRecordConfirm = true
    }

    private func confirmDeleteFile() {
        showingDeleteFileConfirm = true
    }

    private func quarantineFile() {
        Task {
            if !QuarantineManager.shared.canQuarantineFile(at: threat.filePath) {
                showingNetworkWarning = true
                return
            }
            if QuarantineManager.shared.isCrossVolumeQuarantine(at: threat.filePath) {
                showingCrossVolumeWarning = true
                return
            }
            await performQuarantine()
        }
    }
    
    private func performQuarantine() async {
        isQuarantining = true
        quarantineProgress = 0
        
        let success = await QuarantineManager.shared.quarantineFile(
            at: threat.filePath,
            threatName: threat.threatName
        ) { progress in
            Task { @MainActor in quarantineProgress = progress }
        }
        
        isQuarantining = false
        
        if success {
            onActionCompleted()
        }
    }

    private func openInFinder() {
        let folderPath = threat.folderPath
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderPath)
    }

    private func removeRecordOnly() async {
        let folderId: Int64 = 1
        await ScanResultsDatabase.shared.removeRecord(path: threat.filePath, folderId: folderId)
        onActionCompleted()
    }
    
    private func deleteFileFromDisk() async {
        do {
            try FileManager.default.removeItem(atPath: threat.filePath)
            let folderId: Int64 = 1
            await ScanResultsDatabase.shared.removeRecord(path: threat.filePath, folderId: folderId)
            onActionCompleted()
        } catch {
            print("⚠️ Failed to delete: \(error.localizedDescription)")
        }
    }
}

#Preview {
    FoundThreatsView()
}
