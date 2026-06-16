//
//  ContentView.swift
//  ClamGUI
//
//  Main tabbed interface for ClamGUI
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var clamAVManager: ClamAVManager
    @State private var selectedTab = 0
    @State private var isCheckingStatus = true
    @State private var watchdogThreatCount = 0

    var body: some View {
        VStack(spacing: 0) {
            if isCheckingStatus || !clamAVManager.isScannerReady {
                ScannerStatusBanner(isChecking: $isCheckingStatus)
                    .padding([.horizontal, .top])
            }

            TabView(selection: $selectedTab) {
                ScanView()
                    .tabItem {
                        Label("Scan File", systemImage: "doc.badge.gearshape")
                    }
                    .tag(0)

                WatchdogView(onThreatCountChanged: { watchdogThreatCount = $0 })
                    .tabItem {
                        WatchdogTabLabel(threatCount: watchdogThreatCount)
                    }
                    .tag(1)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(2)

                AboutView()
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
                    .tag(3)
                }
        }
        .frame(width: 900, height: 650)
        .padding()
        .onAppear {
            Task {
                await checkStatus()
            }
            refreshWatchdogThreatCount()
        }
    }
    
    private func checkStatus() async {
        isCheckingStatus = true
        await clamAVManager.checkClamAVInstallation()
        isCheckingStatus = false
        await clamAVManager.checkVirusDefinitions()
    }

    private func refreshWatchdogThreatCount() {
        let records = ScanResultsDatabase.shared.getInfectedFiles(folderId: 1)
        watchdogThreatCount = records.count
    }

}

private struct WatchdogTabLabel: View {
    let threatCount: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: threatCount > 0 ? "exclamationmark.shield.fill" : "eye")

            Text("Watchdog")

            if threatCount > 0 {
                Text(displayCount)
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .padding(.horizontal, threatCount > 9 ? 5 : 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(Color.red))
                    .accessibilityLabel("\(threatCount) found threats")
            }
        }
    }

    private var displayCount: String {
        threatCount > 99 ? "99+" : "\(threatCount)"
    }
}

struct ScannerStatusBanner: View {
    @EnvironmentObject var clamAVManager: ClamAVManager
    @Binding var isChecking: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isChecking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: clamAVManager.isScannerRuntimeAvailable ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                    .foregroundColor(clamAVManager.isScannerRuntimeAvailable ? .orange : .red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(isChecking ? "Checking native scanner status..." : clamAVManager.scannerStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)

                if !isChecking && clamAVManager.isScannerRuntimeAvailable && !clamAVManager.isScannerReady {
                    Text("Native databases: ~/Library/Application Support/ClamGUI/Database")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            Button {
                isChecking = true
                Task {
                    await clamAVManager.checkClamAVInstallation()
                    await clamAVManager.checkVirusDefinitions()
                    isChecking = false
                }
            } label: {
                Label(isChecking ? "Checking" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isChecking)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private var title: String {
        if isChecking {
            return "Checking Scanner"
        }
        if !clamAVManager.isScannerRuntimeAvailable {
            return "Scanner Runtime Unavailable"
        }
        return "Scanner Not Ready"
    }
}

#Preview {
    ContentView()
        .environmentObject(ClamAVManager.shared)
        .environmentObject(SettingsManager.shared)
}
