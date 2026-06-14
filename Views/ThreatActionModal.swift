//
//  ThreatActionModal.swift
//  ClamGUI
//
//  Modal dialog for threat detection actions
//

import SwiftUI

struct ThreatActionModal: View {
    @ObservedObject var handler = ThreatActionHandler.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)

                VStack(alignment: .leading) {
                    Text("Threat Found!")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("What do you want to do?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Threat info
            if let threat = handler.currentThreat {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.red)
                        Text("File:")
                            .fontWeight(.medium)
                        Text(threat.fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack {
                        Image(systemName: "virus")
                            .foregroundColor(.red)
                        Text("Threat:")
                            .fontWeight(.medium)
                        Text(threat.threatName)
                            .foregroundColor(.red)
                    }

                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                        Text("Path:")
                            .fontWeight(.medium)
                        Text(threat.filePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.secondary)
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

            Divider()

            // Action buttons
            VStack(spacing: 10) {
                Button(action: {
                    Task {
                        await handler.userSelectedAction(.quarantine)
                    }
                }) {
                    HStack {
                        Image(systemName: "lock.shield")
                        Text("Quarantine File")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .help("Move file to quarantine folder")

                Button(action: {
                    Task {
                        await handler.userSelectedAction(.doNothing)
                    }
                }) {
                    HStack {
                        Image(systemName: "hand.raised")
                        Text("Do Nothing")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Leave file in place")

                Divider()

                Button(action: openInFinder) {
                    Label("Show in Finder", systemImage: "folder")
                }
            }

            Divider()

            // Remember choice checkbox
            HStack {
                Toggle("Remember my choice", isOn: $handler.rememberChoice)
                Spacer()
            }

            if handler.rememberChoice {
                Text("This choice will be applied automatically for future threats")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
        .frame(width: 500)
    }

    private func openInFinder() {
        guard let threat = handler.currentThreat else { return }
        let folderPath = URL(fileURLWithPath: threat.filePath).deletingLastPathComponent().path
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderPath)
    }
}

/// Found Threats Sheet (for viewing all threats)
struct FoundThreatsSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            FoundThreatsView()

            Divider()

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 700, height: 600)
    }
}

#Preview {
    ThreatActionModal()
}
