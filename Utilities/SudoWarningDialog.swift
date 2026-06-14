//
//  SudoWarningDialog.swift
//  ClamGUI
//
//  Warning dialog for launching clamd with sudo privileges
//

import SwiftUI

/// Result of the sudo warning dialog
enum SudoWarningResult {
    case launchWithSudo
    case launchAsUser
    case cancelled
}

/// Sudo warning dialog view
struct SudoWarningDialog: View {
    let onResult: (SudoWarningResult) -> Void
    
    @State private var dontShowAgain = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            // Title
            Text("Security Warning")
                .font(.title)
                .fontWeight(.bold)
            
            // Warning message
            VStack(alignment: .leading, spacing: 10) {
                Text("You're about to launch the ClamAV daemon with administrator privileges.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)

                Text("What this means:")
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                BulletPoint(text: "The daemon can scan files and directories that require root access")
                BulletPoint(text: "The daemon runs with elevated system privileges")
                BulletPoint(text: "Your password will be requested via system authentication")
                BulletPoint(text: "Only use this if you need to scan protected system files")

                Text("Recommendation:")
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)

                BulletPoint(text: "For most users, launching as your user account is sufficient")
                BulletPoint(text: "Use sudo mode only when scanning system directories is required")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            
            // Don't show again
            Toggle("Don't show this warning again", isOn: $dontShowAgain)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Action buttons
            HStack(spacing: 15) {
                Button("Cancel") {
                    onResult(.cancelled)
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Button("Launch as User") {
                    saveDontShowPreference()
                    onResult(.launchAsUser)
                }
                .buttonStyle(.bordered)
                
                Button("Launch with Sudo") {
                    saveDontShowPreference()
                    onResult(.launchWithSudo)
                }
                .buttonStyle(.borderedProminent)
                .background(Color.orange)
            }
        }
        .padding(30)
        .frame(width: 500)
    }
    
    private func saveDontShowPreference() {
        if dontShowAgain {
            SettingsManager.shared.hasShownSudoWarning = true
            SettingsManager.shared.saveSettings()
        }
    }
}

/// Bullet point list item
struct BulletPoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.orange)
            Text(text)
                .font(.system(.body))
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    SudoWarningDialog { _ in }
}
