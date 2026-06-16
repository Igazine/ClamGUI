//
//  ScanPathValidator.swift
//  ClamGUI
//
//  Validates file paths to prevent scanning of system directories
//

import Foundation

/// Validates scanning and action eligibility without privilege escalation.
struct ScanPathValidator {
    struct DirectoryValidation {
        let isAllowed: Bool
        let reason: String?
    }

    struct FileActionCapability {
        let canRead: Bool
        let canDelete: Bool
        let canQuarantine: Bool
        let reason: String?

        var isScanOnly: Bool {
            canRead && (!canDelete || !canQuarantine)
        }
    }
    
    /// System directories that should not be watched recursively.
    private static let restrictedPaths = [
        "/System",
        "/Library",
        "/Applications",
        "/usr",
        "/bin",
        "/sbin",
        "/var",
        "/private",
        "/etc",
        "/dev",
        "/cores",
        "/Network"
    ]
    
    /// Legacy compatibility: these restrictions apply to Watchdog directories,
    /// not to one-off manual file scans.
    static func isPathAllowed(_ path: String) -> Bool {
        validateWatchdogDirectory(path).isAllowed
    }
    
    /// Legacy compatibility for existing callers.
    static func getRestrictionReason(for path: String) -> String? {
        validateWatchdogDirectory(path).reason
    }

    static func validateWatchdogDirectory(_ path: String) -> DirectoryValidation {
        let normalizedPath = NSString(string: path).standardizingPath

        guard !normalizedPath.isEmpty, normalizedPath != "/" else {
            return DirectoryValidation(isAllowed: false, reason: "The root directory cannot be watched.")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return DirectoryValidation(isAllowed: false, reason: "Choose an existing folder.")
        }

        if normalizedPath == "/Volumes" {
            return DirectoryValidation(isAllowed: false, reason: "The Volumes root cannot be watched.")
        }

        for restricted in restrictedPaths {
            if normalizedPath.hasPrefix(restricted + "/") || normalizedPath == restricted {
                return DirectoryValidation(
                    isAllowed: false,
                    reason: "System locations such as \(restricted) cannot be watched recursively."
                )
            }
        }

        guard FileManager.default.isReadableFile(atPath: normalizedPath) else {
            return DirectoryValidation(isAllowed: false, reason: "ClamGUI cannot read this folder with current permissions.")
        }

        guard FileManager.default.isExecutableFile(atPath: normalizedPath) else {
            return DirectoryValidation(isAllowed: false, reason: "ClamGUI cannot enumerate this folder with current permissions.")
        }

        guard FileManager.default.isWritableFile(atPath: normalizedPath) else {
            return DirectoryValidation(isAllowed: false, reason: "ClamGUI cannot write to this folder, so Watchdog actions would be limited.")
        }

        return DirectoryValidation(isAllowed: true, reason: nil)
    }

    static func actionCapability(forFileAt path: String, quarantineDirectory: String) -> FileActionCapability {
        let normalizedPath = NSString(string: path).standardizingPath
        let parentPath = URL(fileURLWithPath: normalizedPath).deletingLastPathComponent().path
        let canRead = FileManager.default.isReadableFile(atPath: normalizedPath)
        let canModifySource = FileManager.default.isWritableFile(atPath: parentPath)
        let canUseQuarantine = canModifySource && canWriteToDirectory(quarantineDirectory)

        if !canRead {
            return FileActionCapability(
                canRead: false,
                canDelete: false,
                canQuarantine: false,
                reason: "ClamGUI cannot read this file with current permissions."
            )
        }

        if !canModifySource {
            return FileActionCapability(
                canRead: true,
                canDelete: false,
                canQuarantine: false,
                reason: "This file is readable, but ClamGUI cannot modify its location with current permissions."
            )
        }

        if !canUseQuarantine {
            return FileActionCapability(
                canRead: true,
                canDelete: true,
                canQuarantine: false,
                reason: "ClamGUI cannot write to the configured quarantine folder."
            )
        }

        return FileActionCapability(canRead: true, canDelete: true, canQuarantine: true, reason: nil)
    }
    
    /// Validate multiple paths and return only allowed ones
    static func filterAllowedPaths(_ paths: [String]) -> [String] {
        return paths.filter { isPathAllowed($0) }
    }
    
    /// Check if path is in user's home directory (safest)
    static func isUserPath(_ path: String) -> Bool {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let normalizedPath = NSString(string: path).standardizingPath
        return normalizedPath.hasPrefix(homeDir + "/") || normalizedPath == homeDir
    }

    private static func canWriteToDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false

        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            return isDirectory.boolValue && FileManager.default.isWritableFile(atPath: path)
        }

        let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: parentPath)
    }
}
