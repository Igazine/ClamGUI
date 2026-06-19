//
//  AboutView.swift
//  ClamGUI
//
//  About tab with application information
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 25) {
            // App Icon
            Image(systemName: "shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            // App Name and Version
            VStack(spacing: 8) {
                Text("ClamGUI")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Description
            Text("A native macOS front-end for ClamAV antivirus")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Info cards
            VStack(spacing: 15) {
                InfoRow(icon: "cpu", title: "Backend", value: "Native libclamav")
                InfoRow(icon: "internaldrive", title: "Database", value: "App-managed signatures")
                InfoRow(icon: "eye", title: "Watchdog", value: "Directory Monitoring")
                InfoRow(icon: "bell", title: "Notifications", value: "Native macOS")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)

            // Links
            VStack(spacing: 12) {
                LinkButton(
                    title: "GitHub Repository",
                    url: "https://github.com/Igazine/ClamGUI",
                    icon: "github"
                )

                LinkButton(
                    title: "ClamAV Documentation",
                    url: "https://docs.clamav.net/",
                    icon: "book"
                )

                LinkButton(
                    title: "Report an Issue",
                    url: "https://github.com/Igazine/ClamGUI/issues",
                    icon: "exclamationmark.bubble"
                )
            }

            // License
            VStack(spacing: 8) {
                Divider()

                Text("License")
                    .font(.headline)

                Text("GNU GPL v2")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Copyright © 2024 ClamGUI. All rights reserved.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: 600)
        .padding()
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - Subviews

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 25)
                .foregroundColor(.accentColor)
            
            Text(title)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct LinkButton: View {
    let title: String
    let url: String
    let icon: String
    
    var body: some View {
        Button(action: {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                
                Text(title)
                
                Spacer()
                
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG && !CLAMGUI_SCRIPTED_BUILD
#Preview {
    AboutView()
}
#endif
