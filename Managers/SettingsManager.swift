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
    @Published var quarantineEnabled: Bool = false
    @Published var quarantinePath: String = ""
    @Published var ignoredFileExtensions: [String] = SettingsManager.defaultIgnoredFileExtensions
    
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

    static let defaultIgnoredFileExtensions: [String] = [
        ".!bt", ".!qB", ".!ut", ".aria2", ".bc!", ".crdownload", ".download",
        ".dtapart", ".fdmdownload", ".filepart", ".jc!", ".opdownload", ".part",
        ".partial", ".qbt", ".qb!", ".tmp", ".temp", ".utpart", ".xlx", ".xxxxxx",
        ".ytdl", ".ytdlpart",
        ".swp", ".swo", ".swn", ".swap", ".lck", ".lock",
        ".bak", ".backup", ".old", ".orig", ".rej",
        ".cache", ".chk", ".dmp", ".dump", ".etl", ".log", ".trace",
        ".icloud", ".downloadpart", ".sdownload", ".safaridownload",
        ".moz-download", ".moz-extension", ".com.apple.timemachine",
        ".part.met", ".met", ".fastresume", ".resume", ".pieces", ".torrentpart"
    ].map { SettingsManager.normalizedExtension($0) }
        .removingDuplicates()
        .sorted()

    static var defaultQuarantinePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClamGUI/Quarantine")
            .path
    }
    
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
            "quarantineEnabled": quarantineEnabled,
            "quarantinePath": quarantinePath,
            "ignoredFileExtensions": ignoredFileExtensions,
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
            $quarantineEnabled.map { _ in }.eraseToAnyPublisher(),
            $quarantinePath.map { _ in }.eraseToAnyPublisher(),
            $ignoredFileExtensions.map { _ in }.eraseToAnyPublisher(),
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
            quarantinePath = Self.defaultQuarantinePath
            loadDatabaseSettings()
            return
        }

        watchDirectory = settings["watchDirectory"] as? String ?? ""
        autoScanOnFileAdded = settings["autoScanOnFileAdded"] as? Bool ?? true
        showNotifications = settings["showNotifications"] as? Bool ?? true
        scanArchives = settings["scanArchives"] as? Bool ?? true
        startAtLogin = settings["startAtLogin"] as? Bool ?? false
        hideMenuBarIcon = settings["hideMenuBarIcon"] as? Bool ?? false
        quarantineEnabled = settings["quarantineEnabled"] as? Bool ?? false
        let storedQuarantinePath = settings["quarantinePath"] as? String ?? ""
        quarantinePath = storedQuarantinePath.isEmpty ? Self.defaultQuarantinePath : storedQuarantinePath
        ignoredFileExtensions = normalizedIgnoredExtensions(
            settings["ignoredFileExtensions"] as? [String] ?? Self.defaultIgnoredFileExtensions
        )
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
        quarantineEnabled = false
        quarantinePath = Self.defaultQuarantinePath
        threatAutoAction = false
        threatAutoActionValue = .quarantine
        clearExecutableBit = false
        ignoredFileExtensions = Self.defaultIgnoredFileExtensions

        // Reset database settings
        dbMaxRecords = DatabaseConfig.maxRecordsPerFolder
        dbRetentionDays = DatabaseConfig.retentionDays
        dbCleanupOnFolderChange = true
        dbAutoMaintenance = true

        saveSettings()
    }

    func addIgnoredExtensions(from input: String) {
        let values = input
            .components(separatedBy: CharacterSet(charactersIn: ", \n\t;"))
            .map(Self.normalizedExtension)
            .filter { !$0.isEmpty }

        ignoredFileExtensions = normalizedIgnoredExtensions(ignoredFileExtensions + values)
    }

    func removeIgnoredExtension(_ extensionValue: String) {
        let normalized = Self.normalizedExtension(extensionValue)
        ignoredFileExtensions.removeAll { $0.caseInsensitiveCompare(normalized) == .orderedSame }
    }

    func resetIgnoredExtensionsToDefaults() {
        ignoredFileExtensions = Self.defaultIgnoredFileExtensions
    }

    func shouldIgnoreFileForScanning(_ url: URL) -> Bool {
        let fileName = url.lastPathComponent.lowercased()
        return ignoredFileExtensions.contains { ignoredExtension in
            fileName.hasSuffix(ignoredExtension.lowercased())
        }
    }

    private func normalizedIgnoredExtensions(_ values: [String]) -> [String] {
        values
            .map(Self.normalizedExtension)
            .filter { !$0.isEmpty }
            .removingDuplicates()
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func normalizedExtension(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let withoutLeadingWildcards = trimmed.replacingOccurrences(of: "*.", with: ".")
        let normalized = withoutLeadingWildcards.hasPrefix(".") ? withoutLeadingWildcards : ".\(withoutLeadingWildcards)"
        return normalized.lowercased()
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

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen = Set<String>()
        return filter { value in
            seen.insert(value.lowercased()).inserted
        }
    }
}
