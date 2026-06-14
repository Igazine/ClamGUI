//
//  ScanPathValidator.swift
//  ClamGUI
//
//  Validates file paths to prevent scanning of system directories
//

import Foundation

/// Validates and restricts scanning of sensitive system directories
struct ScanPathValidator {
    
    /// System directories that should not be scanned
    private static let restrictedPaths = [
        "/System",
        "/Library",
        "/Applications",
        "/usr",
        "/bin",
        "/sbin",
        "/var",
        "/private"
    ]
    
    /// Check if a path is allowed to be scanned
    static func isPathAllowed(_ path: String) -> Bool {
        let normalizedPath = NSString(string: path).standardizingPath
        
        // Check if path starts with any restricted directory
        for restricted in restrictedPaths {
            if normalizedPath.hasPrefix(restricted + "/") || normalizedPath == restricted {
                return false
            }
        }
        
        // Additional checks for root directory
        if normalizedPath == "/" || normalizedPath.isEmpty {
            return false
        }
        
        return true
    }
    
    /// Get reason why path is restricted (if applicable)
    static func getRestrictionReason(for path: String) -> String? {
        if !isPathAllowed(path) {
            let normalizedPath = NSString(string: path).standardizingPath
            
            for restricted in restrictedPaths {
                if normalizedPath.hasPrefix(restricted + "/") || normalizedPath == restricted {
                    return "Scanning of \(restricted) is not allowed for security reasons"
                }
            }
            
            if normalizedPath == "/" || normalizedPath.isEmpty {
                return "Scanning of root directory is not allowed"
            }
        }
        
        return nil
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
}
