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

    var body: some View {
        TabView(selection: $selectedTab) {
            ScanView()
                .tabItem {
                    Label("Scan File", systemImage: "doc.badge.gearshape")
                }
                .tag(0)

            WatchdogView()
                .tabItem {
                    Label("Watchdog", systemImage: "eye")
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
        .frame(width: 900, height: 650)
        .padding()
        .overlay(
            Group {
                if isCheckingStatus {
                    // Show loading state while checking
                    ProgressView("Checking ClamAV status...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.3))
                } else if !clamAVManager.isClamAVInstalled {
                    ClamAVNotInstalledView()
                } else if !clamAVManager.isClamdRunning {
                    ClamAVDaemonNotRunningView()
                } else {
                    EmptyView()
                }
            }
        )
        .onAppear {
            Task {
                await checkStatus()
            }
        }
    }
    
    private func checkStatus() async {
        isCheckingStatus = true
        await clamAVManager.checkClamAVInstallation()
        isCheckingStatus = false
        await clamAVManager.checkVirusDefinitions()
    }
}

struct ClamAVNotInstalledView: View {
    @EnvironmentObject var clamAVManager: ClamAVManager

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)

                Text("ClamAV Not Installed")
                    .font(.title)
                    .fontWeight(.bold)

                Text("ClamGUI requires ClamAV to be installed on your system.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                Button("Install ClamAV") {
                    clamAVManager.openClamAVInstallationPage()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.1))
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
    }
}

struct ClamAVDaemonNotRunningView: View {
    @EnvironmentObject var clamAVManager: ClamAVManager
    @State private var isStarting = false
    @State private var isChecking = false

    var body: some View {
        ZStack {
            // Fully opaque background
            Color.black
                .ignoresSafeArea()

            VStack {
                Spacer()
                VStack(spacing: 20) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)

                    Text("ClamAV Daemon Not Running")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("This app requires the ClamAV daemon (clamd) to be running.\n\nStart the daemon from Settings to begin scanning files.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)

                    HStack(spacing: 15) {
                        Button(action: {
                            isStarting = true
                            Task {
                                await clamAVManager.startClamd()
                                isStarting = false
                                // Auto-check after starting
                                await autoCheckStatus()
                            }
                        }) {
                            HStack {
                                if isStarting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                }
                                Image(systemName: "play.fill")
                                Text(isStarting ? "Starting..." : "Start Daemon")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isStarting)

                        Button("Refresh") {
                            Task {
                                await clamAVManager.checkClamAVInstallation()
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("Daemon socket: ~/Library/Application Support/ClamGUI/clamd.sock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                .padding(40)
                .frame(maxWidth: 500)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .shadow(radius: 20)
                )
                Spacer()
            }
            .padding()
        }
    }

    private func autoCheckStatus() async {
        // Wait for daemon to start, then check status repeatedly
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
            await clamAVManager.checkClamAVInstallation()
            if clamAVManager.isClamdRunning {
                return // Dialog will auto-dismiss
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ClamAVManager.shared)
        .environmentObject(SettingsManager.shared)
}
