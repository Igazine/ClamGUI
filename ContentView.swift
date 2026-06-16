//
//  ContentView.swift
//  ClamGUI
//
//  Main tabbed interface for ClamGUI
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var clamAVManager: ClamAVManager
    @State private var selectedTab: AppTab = .scan
    @State private var isCheckingStatus = true
    @State private var watchdogThreatCount = 0

    var body: some View {
        VStack(spacing: 0) {
            if isCheckingStatus || !clamAVManager.isScannerReady {
                ScannerStatusBanner(isChecking: $isCheckingStatus)
                    .padding([.horizontal, .top])
            }

            ClamGUITabBar(selectedTab: $selectedTab, watchdogThreatCount: watchdogThreatCount)
                .padding(.horizontal)
                .padding(.top, isCheckingStatus || !clamAVManager.isScannerReady ? 10 : 0)
                .padding(.bottom, 8)

            Divider()

            ZStack {
                ScanView()
                    .tabVisibility(.scan, selectedTab: selectedTab)

                WatchdogView(onThreatCountChanged: { watchdogThreatCount = $0 })
                    .tabVisibility(.watchdog, selectedTab: selectedTab)

                SettingsView()
                    .tabVisibility(.settings, selectedTab: selectedTab)

                AboutView()
                    .tabVisibility(.about, selectedTab: selectedTab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private enum AppTab: CaseIterable, Identifiable {
    case scan
    case watchdog
    case settings
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .scan:
            return "Scan File"
        case .watchdog:
            return "Watchdog"
        case .settings:
            return "Settings"
        case .about:
            return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .scan:
            return "doc.badge.gearshape"
        case .watchdog:
            return "eye"
        case .settings:
            return "gearshape"
        case .about:
            return "info.circle"
        }
    }

    func systemImage(threatCount: Int) -> String {
        if self == .watchdog && threatCount > 0 {
            return "exclamationmark.shield.fill"
        }
        return systemImage
    }
}

private struct ClamGUITabBar: View {
    @Binding var selectedTab: AppTab
    let watchdogThreatCount: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                TabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    threatCount: tab == .watchdog ? watchdogThreatCount : 0
                ) {
                    selectedTab = tab
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let threatCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: tab.systemImage(threatCount: threatCount))
                    .font(.system(size: 14, weight: .semibold))

                Text(tab.title)
                    .font(.system(size: 13, weight: .medium))

                if threatCount > 0 {
                    ThreatCountBadge(threatCount: threatCount)
                }
            }
            .foregroundColor(isSelected ? .accentColor : .primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if tab == .watchdog && threatCount > 0 {
            return "Watchdog, \(threatCount) found threats"
        }
        return tab.title
    }
}

private struct ThreatCountBadge: View {
    let threatCount: Int

    var body: some View {
        Text(displayCount)
            .font(.system(size: 10, weight: .bold))
            .monospacedDigit()
            .foregroundColor(.white)
            .padding(.horizontal, threatCount > 9 ? 5 : 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(Color.red))
    }

    private var displayCount: String {
        threatCount > 99 ? "99+" : "\(threatCount)"
    }
}

private extension View {
    func tabVisibility(_ tab: AppTab, selectedTab: AppTab) -> some View {
        let isSelected = tab == selectedTab
        return self
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
