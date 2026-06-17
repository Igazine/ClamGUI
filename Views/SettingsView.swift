//
//  SettingsView.swift
//  ClamGUI
//
//  UI for application settings and configuration
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var clamAVManager: ClamAVManager
    @EnvironmentObject var updaterManager: UpdaterManager
    @ObservedObject private var quarantineManager = QuarantineManager.shared
    
    var body: some View {
        GeometryReader { proxy in
            HStack {
                Spacer(minLength: 0)

                settingsForm
                    .formStyle(.grouped)
                    .frame(
                        width: min(proxy.size.width - 48, 820),
                        height: max(proxy.size.height - 36, 0)
                    )
                    .padding(.vertical, 18)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            Task {
                await clamAVManager.checkVirusDefinitions()
            }
        }
    }

    private var settingsForm: some View {
        Form {
            watchdogSection
            IgnoredExtensionsSettingsSection()
            notificationsSection
            quarantineSection
            threatDetectionSection
            virusDefinitionsSection
            applicationSection
            clamAVStatusSection
            databaseSection
            resetSection
        }
    }

    private var watchdogSection: some View {
        Section {
            Toggle("Auto-scan files when added", isOn: $settingsManager.autoScanOnFileAdded)
            Toggle("Scan archives recursively", isOn: $settingsManager.scanArchives)
        } header: {
            Text("Watchdog")
        } footer: {
            Text("Watchdog monitors the selected directory and scans new or modified files while active.")
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Show notifications", isOn: $settingsManager.showNotifications)

            if settingsManager.showNotifications {
                Toggle("Notify on threat detection", isOn: .constant(true))
                    .disabled(true)
            }
        }
    }

    private var quarantineSection: some View {
        Section("Quarantine") {
            Toggle("Enable quarantine for infected files", isOn: $settingsManager.quarantineEnabled)

            if settingsManager.quarantineEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Quarantine location")
                        Spacer()
                        Button("Change...") {
                            selectQuarantinePath()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(settingsManager.quarantinePath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    Button("Open in Finder") {
                        QuarantineManager.shared.openQuarantineDirectory()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }

            if !quarantineManager.quarantinedFiles.isEmpty {
                QuarantineInventoryView()
            }

            Label("Quarantined files are moved to a secure location", systemImage: "lock.shield")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var threatDetectionSection: some View {
        Section("Threat Detection") {
            VStack(alignment: .leading, spacing: 10) {
                Text("When a threat is detected:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Auto-apply action without showing dialog", isOn: $settingsManager.threatAutoAction)

                if settingsManager.threatAutoAction {
                    Picker("Action to take:", selection: $settingsManager.threatAutoActionValue) {
                        ForEach(ThreatAction.allCases) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .padding(.leading)
                } else {
                    Text("Show dialog with action choices")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading)
                }

                Divider()

                Toggle("Clear executable bit on found threats", isOn: $settingsManager.clearExecutableBit)

                HStack {
                    Spacer()
                    if settingsManager.threatAutoAction {
                        Button("Reset remembered choice") {
                            ThreatActionHandler.shared.clearRememberedAction()
                        }
                    }
                }
            }
        }
    }

    private var virusDefinitionsSection: some View {
        Section("Virus Definitions") {
            HStack {
                Text("Version")
                Spacer()
                Text(clamAVManager.virusDefinitionsVersion)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Status")
                Spacer()

                if clamAVManager.virusDefinitionsOutdated {
                    Label("Outdated", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                } else {
                    Label("Up to date", systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                }
            }

            Button(action: {
                clamAVManager.updateVirusDefinitions()
            }) {
                HStack {
                    if clamAVManager.isUpdatingVirusDefinitions {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(clamAVManager.isUpdatingVirusDefinitions ? "Updating..." : "Update Definitions")
                }
            }
            .disabled(clamAVManager.isUpdatingVirusDefinitions)

            Text("Databases are stored in ~/Library/Application Support/ClamGUI/Database.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let message = clamAVManager.virusDefinitionsUpdateMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(message.localizedCaseInsensitiveContains("error") || message.localizedCaseInsensitiveContains("failed") ? .red : .secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var applicationSection: some View {
        Section("Application") {
            Toggle("Start ClamGUI at login", isOn: $settingsManager.startAtLogin)
                .onChange(of: settingsManager.startAtLogin) { _ in
                    settingsManager.toggleStartAtLogin()
                }

            Toggle("Show in menu bar", isOn: Binding(
                get: { !settingsManager.hideMenuBarIcon },
                set: { settingsManager.hideMenuBarIcon = !$0 }
            ))

            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundColor(.secondary)

                Button(action: {
                    Task { @MainActor in
                        await updaterManager.checkForUpdates()
                        if updaterManager.updateAvailable {
                            updaterManager.showUpdateAlert()
                        }
                    }
                }) {
                    Text("Check for Updates")
                }
                .disabled(updaterManager.isCheckingForUpdates)
            }

            if updaterManager.isCheckingForUpdates {
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
    }

    private var clamAVStatusSection: some View {
        Section("ClamAV Status") {
            HStack {
                Text("Scanner")
                Spacer()

                Label(clamAVManager.activeScannerName, systemImage: clamAVManager.isScannerReady ? "shield.checkered" : "exclamationmark.triangle")
                    .foregroundColor(clamAVManager.isScannerReady ? .green : .orange)
            }

            Text(clamAVManager.scannerStatusMessage)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("Scanner Runtime")
                Spacer()

                if clamAVManager.isScannerReady {
                    Label("Ready", systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                } else if clamAVManager.isScannerRuntimeAvailable {
                    Label("Available", systemImage: "checkmark.circle")
                        .foregroundColor(.orange)
                } else {
                    Label("Unavailable", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var databaseSection: some View {
        Section {
            HStack {
                Text("Max records")
                Spacer()
                TextField("", value: $settingsManager.dbMaxRecords, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }

            HStack {
                Text("Retention period")
                Spacer()
                TextField("", value: $settingsManager.dbRetentionDays, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text("days")
                    .foregroundColor(.secondary)
            }

            Toggle("Clean up on folder change", isOn: $settingsManager.dbCleanupOnFolderChange)
            Toggle("Automatic maintenance", isOn: $settingsManager.dbAutoMaintenance)

            Label("Database automatically removes old records and verifies files exist", systemImage: "externaldrive.badge.checkmark")
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text("Scan History Database")
        } footer: {
            Text("When record count exceeds the maximum, oldest records are removed. Files older than the retention period are also deleted.")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset to Defaults") {
                settingsManager.resetToDefaults()
            }
            .foregroundColor(.red)
        }
    }

    // MARK: - Helper Methods

    private func selectQuarantinePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select quarantine directory"
        panel.directoryURL = URL(fileURLWithPath: settingsManager.quarantinePath)

        panel.begin { response in
            if response == .OK, let url = panel.url {
                settingsManager.quarantinePath = url.path
                settingsManager.saveSettings()
            }
        }
    }
}

private struct QuarantineInventoryView: View {
    @ObservedObject private var quarantineManager = QuarantineManager.shared
    @State private var busyFileId: UUID?

    private var displayedFiles: [QuarantinedFile] {
        Array(quarantineManager.quarantinedFiles.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack {
                Label("Quarantined Files", systemImage: "lock.doc")
                    .font(.headline)

                Spacer()

                Text("\(quarantineManager.quarantinedFiles.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(displayedFiles) { file in
                    QuarantineInventoryRow(
                        file: file,
                        isBusy: busyFileId == file.id,
                        onRestore: { restore(file) },
                        onDelete: { delete(file) },
                        onReveal: { reveal(file) }
                    )
                }
            }

            if quarantineManager.quarantinedFiles.count > displayedFiles.count {
                Text("\(quarantineManager.quarantinedFiles.count - displayedFiles.count) more quarantined file(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private func restore(_ file: QuarantinedFile) {
        busyFileId = file.id
        Task {
            _ = await quarantineManager.restoreFile(file)
            await MainActor.run { busyFileId = nil }
        }
    }

    private func delete(_ file: QuarantinedFile) {
        busyFileId = file.id
        Task {
            _ = await quarantineManager.deleteFile(file)
            await MainActor.run { busyFileId = nil }
        }
    }

    private func reveal(_ file: QuarantinedFile) {
        NSWorkspace.shared.selectFile(file.quarantinePath, inFileViewerRootedAtPath: "")
    }
}

private struct QuarantineInventoryRow: View {
    let file: QuarantinedFile
    let isBusy: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void
    let onReveal: () -> Void
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: file.originalPath).lastPathComponent)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(file.threatName)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(1)

                Text(file.originalPath)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(formatFileSize(UInt64(max(file.fileSize, 0))))
                .font(.caption2)
                .foregroundColor(.secondary)

            if isBusy {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Button("Show", action: onReveal)
                    .buttonStyle(.bordered)

                Button("Restore", action: onRestore)
                    .buttonStyle(.bordered)

                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                    .buttonStyle(.bordered)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
        .alert("Delete Quarantined File", isPresented: $showingDeleteConfirmation) {
            Button("Delete File", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the quarantined copy. The original file has already been moved out of its original location.")
        }
    }
}

private struct IgnoredExtensionsSettingsSection: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var newExtension = ""

    private let columns = [
        GridItem(.adaptive(minimum: 86), spacing: 8)
    ]

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField(".crdownload", text: $newExtension)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addExtensions)

                    Button {
                        addExtensions()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(newExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Restore Defaults") {
                        settingsManager.resetIgnoredExtensionsToDefaults()
                    }
                }

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(settingsManager.ignoredFileExtensions, id: \.self) { extensionValue in
                            IgnoredExtensionToken(extensionValue: extensionValue) {
                                settingsManager.removeIgnoredExtension(extensionValue)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 90, maxHeight: 150)
            }
        } header: {
            Text("Ignored File Extensions")
        } footer: {
            Text("Watchdog skips files with these suffixes, useful for partial downloads and files that are constantly modified until complete. Add multiple entries separated by spaces, commas, or semicolons.")
        }
    }

    private func addExtensions() {
        settingsManager.addIgnoredExtensions(from: newExtension)
        newExtension = ""
    }
}

private struct IgnoredExtensionToken: View {
    let extensionValue: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(extensionValue)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(extensionValue)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
        )
    }
}

#Preview {
    SettingsView()
        .environmentObject(ClamAVManager.shared)
        .environmentObject(SettingsManager.shared)
        .environmentObject(UpdaterManager.shared)
}
