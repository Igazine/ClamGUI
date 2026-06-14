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
    
    var body: some View {
        Form {
            // Watchdog Settings
            Section {
                Toggle("Auto-scan files when added", isOn: $settingsManager.autoScanOnFileAdded)

                HStack {
                    Text("Max scan size")
                    Spacer()
                    TextField("", value: $settingsManager.maxScanSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("MB")
                        .foregroundColor(.secondary)
                }

                Toggle("Scan archives recursively", isOn: $settingsManager.scanArchives)
            } header: {
                Text("Watchdog")
            } footer: {
                Text("Max scan size limits how much data ClamAV scans per file. Files larger than this will be skipped. This protects against denial-of-service attacks using huge files.")
            }
            
            // Notifications
            Section("Notifications") {
                Toggle("Show notifications", isOn: $settingsManager.showNotifications)

                if settingsManager.showNotifications {
                    Toggle("Notify on threat detection", isOn: .constant(true))
                        .disabled(true) // Always enabled when notifications are on
                }
            }

            // Quarantine
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

                Label("Quarantined files are moved to a secure location", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Threat Detection
            Section("Threat Detection") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("When a threat is detected:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Auto-action toggle
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

                    // Clear executable bit
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
            // Virus Definitions
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
            
            // Application
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
            
            // ClamAV Status
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
                    } else if clamAVManager.isClamAVInstalled {
                        Label("Available", systemImage: "checkmark.circle")
                            .foregroundColor(.orange)
                    } else {
                        Label("Unavailable", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }

                HStack {
                    Text("Legacy Daemon")
                    Spacer()

                    if clamAVManager.activeScannerName == ScannerBackend.clamd.rawValue {
                        Label("Running", systemImage: "play.circle")
                            .foregroundColor(.green)
                    } else if clamAVManager.isClamAVInstalled {
                        Label("Inactive", systemImage: "stop.circle")
                            .foregroundColor(.secondary)
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }

                // Daemon controls
                if clamAVManager.isClamAVInstalled && clamAVManager.activeScannerName != ScannerBackend.nativeLibClamAV.rawValue {
                    HStack {
                        if clamAVManager.activeScannerName == ScannerBackend.clamd.rawValue {
                            Button(action: {
                                Task {
                                    await clamAVManager.restartClamd()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Restart Daemon")
                                }
                            }
                            .disabled(clamAVManager.isStartingClamd)

                            Button(action: {
                                Task {
                                    await clamAVManager.stopClamd()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "stop.fill")
                                    Text("Stop Daemon")
                                }
                            }
                            .foregroundColor(.red)
                            .disabled(clamAVManager.isStartingClamd)
                        } else {
                            Button(action: {
                                Task {
                                    await clamAVManager.startClamd()
                                }
                            }) {
                                HStack {
                                    if clamAVManager.isStartingClamd {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "play.fill")
                                    }
                                    Text(clamAVManager.isStartingClamd ? "Starting..." : "Start Daemon")
                                }
                                .frame(minWidth: 120)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(clamAVManager.isStartingClamd)
                        }
                    }
                    
                    // Show error message if startup failed
                    if let errorMessage = clamAVManager.clamdStartError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Text("Daemon runs as your user account. No sudo required.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !clamAVManager.isClamAVInstalled {
                    Button(action: {
                        clamAVManager.openClamAVInstallationPage()
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Install ClamAV")
                        }
                    }
                }
            }
            
            // Database
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

            // Reset
            Section {
                Button("Reset to Defaults") {
                    settingsManager.resetToDefaults()
                }
                .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            Task {
                await clamAVManager.checkVirusDefinitions()
            }
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

#Preview {
    SettingsView()
        .environmentObject(ClamAVManager.shared)
        .environmentObject(SettingsManager.shared)
        .environmentObject(UpdaterManager.shared)
}
