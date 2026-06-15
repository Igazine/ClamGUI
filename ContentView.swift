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
                } else if !clamAVManager.isScannerRuntimeAvailable {
                    ScannerUnavailableView()
                } else if !clamAVManager.isScannerReady {
                    ScannerNotReadyView()
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

struct ScannerUnavailableView: View {
    @EnvironmentObject var clamAVManager: ClamAVManager

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)

                Text("Scanner Runtime Unavailable")
                    .font(.title)
                    .fontWeight(.bold)

                Text(clamAVManager.scannerStatusMessage)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                Text("For development builds, run the packaged debug build script so libclamav is embedded in the app bundle.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
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

struct ScannerNotReadyView: View {
    @EnvironmentObject var clamAVManager: ClamAVManager
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

                    Text("Scanner Not Ready")
                        .font(.title)
                        .fontWeight(.bold)

                    Text(clamAVManager.scannerStatusMessage)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)

                    HStack(spacing: 15) {
                        Button(action: {
                            isChecking = true
                            Task {
                                await clamAVManager.checkClamAVInstallation()
                                await clamAVManager.checkVirusDefinitions()
                                isChecking = false
                            }
                        }) {
                            HStack {
                                if isChecking {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                }
                                Image(systemName: "arrow.clockwise")
                                Text(isChecking ? "Checking..." : "Refresh")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isChecking)
                    }

                    Text("Native databases: ~/Library/Application Support/ClamGUI/Database")
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
}

#Preview {
    ContentView()
        .environmentObject(ClamAVManager.shared)
        .environmentObject(SettingsManager.shared)
}
