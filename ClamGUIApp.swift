//
//  ClamGUIApp.swift
//  ClamGUI
//
//  ClamAV Graphical User Interface for macOS
//

import SwiftUI

@main
struct ClamGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var clamAVManager = ClamAVManager.shared
    @ObservedObject private var updaterManager = UpdaterManager.shared

    var body: some Scene {
        WindowGroup {
            if NativeScannerSmokeTest.isEnabled {
                EmptyView()
            } else {
                ContentView()
                    .environmentObject(settingsManager)
                    .environmentObject(clamAVManager)
                    .environmentObject(updaterManager)
                    .onAppear {
                        Task {
                            print("🔍 Checking ClamAV installation...")
                            await clamAVManager.checkClamAVInstallation()
                            print("📊 ClamAV Status: installed=\(clamAVManager.isClamAVInstalled), scannerReady=\(clamAVManager.isScannerReady)")
                            await clamAVManager.checkVirusDefinitions()
                        }
                    }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit ClamGUI") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NativeScannerSmokeTest.isEnabled {
            NativeScannerSmokeTest.runAndExit()
            return
        }

        // Initialize menu bar icon
        menuBarManager = MenuBarManager.shared

        // Show main window on launch
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when window is closed - menu bar app
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Stop clamd daemon and send SHUTDOWN command before quitting
        Task {
            await ClamAVManager.shared.stopClamd()
            ClamAVManager.shared.closeSocketConnection()
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure clamd is stopped and SHUTDOWN command was sent
        Task { @MainActor in
            await ClamAVManager.shared.stopClamd()
            ClamAVManager.shared.closeSocketConnection()
        }
    }
}
