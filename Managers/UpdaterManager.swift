//
//  UpdaterManager.swift
//  ClamGUI
//
//  Handles ClamGUI application updates
//

import Foundation
import AppKit

/// Manages ClamGUI application updates
@MainActor
class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()
    
    @Published var isCheckingForUpdates = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var releaseNotes: String?
    
    // GitHub repository configuration
    private let githubOwner = "clamgui" // Update when repo is created
    private let githubRepo = "clamgui"
    
    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    
    private init() {}
    
    // MARK: - Update Check
    
    func checkForUpdates() async {
        isCheckingForUpdates = true
        
        guard let url = URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest") else {
            isCheckingForUpdates = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                isCheckingForUpdates = false
                return
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = json["tag_name"] as? String,
               let notes = json["body"] as? String {
                
                let cleanVersion = version.replacingOccurrences(of: "v", with: "")
                latestVersion = cleanVersion
                releaseNotes = notes
                
                updateAvailable = isVersionNewer(cleanVersion, than: currentVersion)
            }
        } catch {
            print("Update check failed: \(error.localizedDescription)")
        }
        
        isCheckingForUpdates = false
    }
    
    // MARK: - Version Comparison
    
    private func isVersionNewer(_ newVersion: String, than currentVersion: String) -> Bool {
        let newComponents = newVersion.split(separator: ".").compactMap { Int($0) }
        let currentComponents = currentVersion.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(newComponents.count, currentComponents.count) {
            let newComponent = i < newComponents.count ? newComponents[i] : 0
            let currentComponent = i < currentComponents.count ? currentComponents[i] : 0
            
            if newComponent > currentComponent {
                return true
            } else if newComponent < currentComponent {
                return false
            }
        }
        
        return false
    }
    
    // MARK: - Update Actions
    
    func downloadAndInstallUpdate() {
        guard let latestVersion = latestVersion else { return }
        
        // Open GitHub releases page
        if let url = URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/releases") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func showUpdateAlert() {
        guard let latestVersion = latestVersion else { return }
        
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Version \(latestVersion) is now available.\n\n\(releaseNotes ?? "")"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            downloadAndInstallUpdate()
        }
    }
}
