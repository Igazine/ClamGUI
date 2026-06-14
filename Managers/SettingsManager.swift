//
//  SettingsManager.swift
//  ClamGUI
//
//  Manages application settings and preferences
//

import Foundation
import Combine
import AppKit

/// Manages user preferences and application configuration
@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // MARK: - Published Settings

    @Published var watchDirectory: String = ""
    @Published var autoScanOnFileAdded: Bool = true
    @Published var showNotifications: Bool = true
    @Published var scanArchives: Bool = true
    @Published var startAtLogin: Bool = false
    @Published var hideMenuBarIcon: Bool = false
    @Published var launchClamdWithSudo: Bool = false
    @Published var hasShownSudoWarning: Bool = false
    @Published var quarantineEnabled: Bool = false
    @Published var quarantinePath: String = ""
    
    // Database retention settings
    @Published var dbMaxRecords: Int = 500_000
    @Published var dbRetentionDays: Int = 90
    @Published var dbCleanupOnFolderChange: Bool = true
    @Published var dbAutoMaintenance: Bool = true
    
    // Threat action settings
    @Published var threatAutoAction: Bool = false  // If true, use threatAutoActionValue without showing modal
    @Published var threatAutoActionValue: ThreatAction = .quarantine  // Action to take automatically
    @Published var clearExecutableBit: Bool = false  // Clear executable bit on found threats

    // MARK: - Constants

    private let userDefaultsKey = "com.clamgui.settings"
    private let dbSettingsKey = "com.clamgui.dbsettings"
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        loadSettings()
        setupAutosave()
    }
    
    // MARK: - Settings Persistence

    func saveSettings() {
        let settings: [String: Any] = [
            "watchDirectory": watchDirectory,
            "autoScanOnFileAdded": autoScanOnFileAdded,
            "showNotifications": showNotifications,
            "scanArchives": scanArchives,
            "startAtLogin": startAtLogin,
            "hideMenuBarIcon": hideMenuBarIcon,
            "launchClamdWithSudo": launchClamdWithSudo,
            "hasShownSudoWarning": hasShownSudoWarning,
            "quarantineEnabled": quarantineEnabled,
            "quarantinePath": quarantinePath,
            "threatAutoAction": threatAutoAction,
            "threatAutoActionValue": threatAutoActionValue.rawValue,
            "clearExecutableBit": clearExecutableBit
        ]

        UserDefaults.standard.set(settings, forKey: userDefaultsKey)

        // Save database settings separately
        let dbSettings: [String: Any] = [
            "dbMaxRecords": dbMaxRecords,
            "dbRetentionDays": dbRetentionDays,
            "dbCleanupOnFolderChange": dbCleanupOnFolderChange,
            "dbAutoMaintenance": dbAutoMaintenance
        ]
        UserDefaults.standard.set(dbSettings, forKey: dbSettingsKey)
    }

    private func setupAutosave() {
        let settingsPublishers: [AnyPublisher<Void, Never>] = [
            $watchDirectory.map { _ in }.eraseToAnyPublisher(),
            $autoScanOnFileAdded.map { _ in }.eraseToAnyPublisher(),
            $showNotifications.map { _ in }.eraseToAnyPublisher(),
            $scanArchives.map { _ in }.eraseToAnyPublisher(),
            $startAtLogin.map { _ in }.eraseToAnyPublisher(),
            $hideMenuBarIcon.map { _ in }.eraseToAnyPublisher(),
            $launchClamdWithSudo.map { _ in }.eraseToAnyPublisher(),
            $hasShownSudoWarning.map { _ in }.eraseToAnyPublisher(),
            $quarantineEnabled.map { _ in }.eraseToAnyPublisher(),
            $quarantinePath.map { _ in }.eraseToAnyPublisher(),
            $dbMaxRecords.map { _ in }.eraseToAnyPublisher(),
            $dbRetentionDays.map { _ in }.eraseToAnyPublisher(),
            $dbCleanupOnFolderChange.map { _ in }.eraseToAnyPublisher(),
            $dbAutoMaintenance.map { _ in }.eraseToAnyPublisher(),
            $threatAutoAction.map { _ in }.eraseToAnyPublisher(),
            $threatAutoActionValue.map { _ in }.eraseToAnyPublisher(),
            $clearExecutableBit.map { _ in }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(settingsPublishers)
            .dropFirst(settingsPublishers.count)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.saveSettings()
            }
            .store(in: &cancellables)
    }

    func loadSettings() {
        guard let settings = UserDefaults.standard.dictionary(forKey: userDefaultsKey) else {
            // Set default quarantine path on first load
            let defaultQuarantinePath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/ClamGUI/Quarantine")
                .path
            quarantinePath = defaultQuarantinePath
            loadDatabaseSettings()
            return
        }

        watchDirectory = settings["watchDirectory"] as? String ?? ""
        autoScanOnFileAdded = settings["autoScanOnFileAdded"] as? Bool ?? true
        showNotifications = settings["showNotifications"] as? Bool ?? true
        scanArchives = settings["scanArchives"] as? Bool ?? true
        startAtLogin = settings["startAtLogin"] as? Bool ?? false
        hideMenuBarIcon = settings["hideMenuBarIcon"] as? Bool ?? false
        launchClamdWithSudo = settings["launchClamdWithSudo"] as? Bool ?? false
        hasShownSudoWarning = settings["hasShownSudoWarning"] as? Bool ?? false
        quarantineEnabled = settings["quarantineEnabled"] as? Bool ?? false
        quarantinePath = settings["quarantinePath"] as? String ?? ""
        threatAutoAction = settings["threatAutoAction"] as? Bool ?? false
        if let actionValue = settings["threatAutoActionValue"] as? String,
           let action = ThreatAction(rawValue: actionValue) {
            threatAutoActionValue = action
        }
        clearExecutableBit = settings["clearExecutableBit"] as? Bool ?? false

        loadDatabaseSettings()
    }
    
    private func loadDatabaseSettings() {
        guard let dbSettings = UserDefaults.standard.dictionary(forKey: dbSettingsKey) else {
            // Use defaults
            dbMaxRecords = DatabaseConfig.maxRecordsPerFolder
            dbRetentionDays = DatabaseConfig.retentionDays
            dbCleanupOnFolderChange = true
            dbAutoMaintenance = true
            return
        }
        
        dbMaxRecords = dbSettings["dbMaxRecords"] as? Int ?? DatabaseConfig.maxRecordsPerFolder
        dbRetentionDays = dbSettings["dbRetentionDays"] as? Int ?? DatabaseConfig.retentionDays
        dbCleanupOnFolderChange = dbSettings["dbCleanupOnFolderChange"] as? Bool ?? true
        dbAutoMaintenance = dbSettings["dbAutoMaintenance"] as? Bool ?? true
    }

    func resetToDefaults() {
        watchDirectory = ""
        autoScanOnFileAdded = true
        showNotifications = true
        scanArchives = true
        startAtLogin = false
        hideMenuBarIcon = false
        launchClamdWithSudo = false
        hasShownSudoWarning = false
        quarantineEnabled = false
        let defaultQuarantinePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClamGUI/Quarantine")
            .path
        quarantinePath = defaultQuarantinePath
        threatAutoAction = false
        threatAutoActionValue = .quarantine
        clearExecutableBit = false

        // Reset database settings
        dbMaxRecords = DatabaseConfig.maxRecordsPerFolder
        dbRetentionDays = DatabaseConfig.retentionDays
        dbCleanupOnFolderChange = true
        dbAutoMaintenance = true

        saveSettings()
    }

    // MARK: - Login Item Management

    func toggleStartAtLogin() {
        if startAtLogin {
            enableLoginItem()
        } else {
            disableLoginItem()
        }
    }

    private func enableLoginItem() {
        let appPath = Bundle.main.bundlePath
        let script = """
        tell application "System Events"
            if not (exists login item "ClamGUI") then
                make new login item at end with properties {path:"\(appPath)", enabled:true}
            end if
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    private func disableLoginItem() {
        let script = """
        tell application "System Events"
            if exists login item "ClamGUI" then
                delete login item "ClamGUI"
            end if
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }
}
