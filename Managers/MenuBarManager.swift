//
//  MenuBarManager.swift
//  ClamGUI
//
//  Manages the menu bar icon and menu items
//

import SwiftUI
import AppKit

/// Manages the menu bar icon and its associated menu
@MainActor
class MenuBarManager: NSObject, ObservableObject {
    static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    
    @Published var isScanning = false
    @Published var lastScanDate: Date?
    @Published var threatsFound: Int = 0
    
    override private init() {
        super.init()
        setupMenuBar()
    }
    
    // MARK: - Menu Bar Setup
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: "ClamGUI")
            button.action = #selector(showMenu)
            button.target = self
        }
        
        menu = NSMenu()
        setupMenuItems()
    }
    
    private func setupMenuItems() {
        guard let menu = menu else { return }
        
        menu.removeAllItems()
        
        // App name header
        let headerItem = NSMenuItem(title: "ClamGUI", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quick Scan
        let scanItem = NSMenuItem(title: "Quick Scan...", action: #selector(quickScan), keyEquivalent: "s")
        scanItem.target = self
        scanItem.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Scan")
        menu.addItem(scanItem)
        
        // Open Main Window
        let openItem = NSMenuItem(title: "Open ClamGUI", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "window.shade", accessibilityDescription: "Open")
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Update Definitions
        let updateItem = NSMenuItem(title: "Update Definitions...", action: #selector(updateDefinitions), keyEquivalent: "u")
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Update")
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // About
        let aboutItem = NSMenuItem(title: "About ClamGUI", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")
        menu.addItem(aboutItem)
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit ClamGUI", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Quit")
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    // MARK: - Menu Actions
    
    @objc private func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: statusItem?.button)
    }
    
    @objc private func quickScan() {
        // Show file picker for quick scan
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select a file to scan"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    await ClamAVManager.shared.scanFile(at: url.path)
                }
            }
        }
    }
    
    @objc private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            window.center()
        }
    }
    
    @objc private func updateDefinitions() {
        Task { @MainActor in
            ClamAVManager.shared.updateVirusDefinitions()
        }
    }
    
    @objc private func openSettings() {
        openMainWindow()
        // Would navigate to settings tab
    }
    
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Status Updates
    
    func updateScanStatus(isScanning: Bool) {
        self.isScanning = isScanning
        
        if let button = statusItem?.button {
            if isScanning {
                button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Scanning")
            } else {
                button.image = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: "ClamGUI")
            }
        }
    }
    
    func notifyThreatFound() {
        threatsFound += 1
        lastScanDate = Date()
        
        // Could add badge or indicator here
    }
}
