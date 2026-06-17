//
//  ThreatActionHandler.swift
//  ClamGUI
//
//  Handles threat detection actions and user choices
//

import Foundation
import SwiftUI

/// Available actions when a threat is detected
enum ThreatAction: String, CaseIterable, Identifiable {
    case quarantine
    case doNothing
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .quarantine:
            return "Quarantine"
        case .doNothing:
            return "Do Nothing"
        }
    }
}

/// Manages threat detection responses and user choices
@MainActor
class ThreatActionHandler: ObservableObject {
    static let shared = ThreatActionHandler()
    
    // Published state for UI
    @Published var showingThreatModal = false
    @Published var currentThreat: ThreatInfo?
    @Published var rememberChoice = false
    
    // Persisted settings
    @AppStorage("threatRememberedAction") private var rememberedActionRaw: String = ""
    @AppStorage("threatAutoActionEnabled") var autoActionEnabled: Bool = false
    
    var rememberedAction: ThreatAction? {
        ThreatAction(rawValue: rememberedActionRaw)
    }
    
    /// Called when a threat is detected
    func handleThreatDetected(filePath: String, threatName: String) async {
        print("⚠️ handleThreatDetected called: path='\(filePath)', threat='\(threatName)'")
        print("   rememberedAction=\(rememberedAction?.rawValue ?? "nil")")
        print("   threatAutoAction=\(SettingsManager.shared.threatAutoAction)")
        print("   threatAutoActionValue=\(SettingsManager.shared.threatAutoActionValue)")
        let capability = ScanPathValidator.actionCapability(
            forFileAt: filePath,
            quarantineDirectory: SettingsManager.shared.quarantinePath
        )
        
        // Check if we have an auto-action set
        if let action = rememberedAction {
            guard action.isAllowed(by: capability) else {
                showModal(filePath: filePath, threatName: threatName, capability: capability)
                return
            }
            print("   → Executing remembered action: \(action)")
            await executeAction(action, filePath: filePath, threatName: threatName, capability: capability)
            return
        }

        // Check if settings has auto-action configured
        if SettingsManager.shared.threatAutoAction {
            guard SettingsManager.shared.threatAutoActionValue.isAllowed(by: capability) else {
                showModal(filePath: filePath, threatName: threatName, capability: capability)
                return
            }
            print("   → Executing settings auto-action: \(SettingsManager.shared.threatAutoActionValue)")
            await executeAction(SettingsManager.shared.threatAutoActionValue, filePath: filePath, threatName: threatName, capability: capability)
            return
        }

        // Show modal and let the user choose how to handle the threat.
        showModal(filePath: filePath, threatName: threatName, capability: capability)
    }

    private func showModal(filePath: String, threatName: String, capability: ScanPathValidator.FileActionCapability) {
        print("   → Showing threat action modal")
        currentThreat = ThreatInfo(filePath: filePath, threatName: threatName, actionCapability: capability)
        showingThreatModal = true
        print("   → showingThreatModal=\(showingThreatModal)")
        rememberChoice = false
    }
    
    /// User selected an action in the modal
    func userSelectedAction(_ action: ThreatAction) async {
        guard let threat = currentThreat else { return }
        guard action.isAllowed(by: threat.actionCapability) else { return }
        
        // Save choice if requested
        if rememberChoice {
            rememberedActionRaw = action.rawValue
            autoActionEnabled = true
        }
        
        // Execute the action
        await executeAction(action, filePath: threat.filePath, threatName: threat.threatName, capability: threat.actionCapability)
        
        // Close modal
        showingThreatModal = false
        currentThreat = nil
    }
    
    /// Execute a threat action
    private func executeAction(
        _ action: ThreatAction,
        filePath: String,
        threatName: String,
        capability: ScanPathValidator.FileActionCapability
    ) async {
        // Clear executable bit if setting is enabled
        if SettingsManager.shared.clearExecutableBit && capability.canDelete {
            await clearExecutableBit(for: filePath)
        }
        
        switch action {
        case .quarantine:
            if await QuarantineManager.shared.quarantineFile(at: filePath, threatName: threatName) {
                print("✅ Quarantined: \(filePath)")
                await ScanResultsDatabase.shared.removeRecord(path: filePath, folderId: 1)
                await updateThreatRecord(filePath: filePath, action: "quarantined")
            } else {
                print("⚠️ Failed to quarantine: \(filePath)")
            }

        case .doNothing:
            print("ℹ️ Doing nothing for: \(filePath)")
            await updateThreatRecord(filePath: filePath, action: "ignored")
        }
    }
    
    /// Update the database record with action taken
    private func updateThreatRecord(filePath: String, action: String) async {
        // For the single-table design, we just log the action
        // The record stays in the database with status = 'infected'
        print("📝 Threat action recorded: path='\(filePath)', action=\(action)")
    }
    
    /// Clear executable bit on a file
    private func clearExecutableBit(for filePath: String) async {
        let fileManager = FileManager.default
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: filePath)
            if let permissions = attributes[.posixPermissions] as? NSNumber {
                // Remove execute bits (mask out 0o111)
                let newPermissions = permissions.intValue & ~0o111
                try fileManager.setAttributes([.posixPermissions: NSNumber(value: newPermissions)], ofItemAtPath: filePath)
                print("✅ Cleared executable bit: \(filePath)")
            }
        } catch {
            print("⚠️ Failed to clear executable bit: \(error.localizedDescription)")
        }
    }
    
    /// Clear remembered action
    func clearRememberedAction() {
        rememberedActionRaw = ""
        autoActionEnabled = false
    }
}

/// Threat information for display
struct ThreatInfo: Identifiable {
    let id = UUID()
    let filePath: String
    let threatName: String
    let actionCapability: ScanPathValidator.FileActionCapability
    let detectedAt = Date()
    
    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
    
    var folderPath: String {
        URL(fileURLWithPath: filePath).deletingLastPathComponent().path
    }
}

private extension ThreatAction {
    func isAllowed(by capability: ScanPathValidator.FileActionCapability) -> Bool {
        switch self {
        case .quarantine:
            return capability.canQuarantine
        case .doNothing:
            return true
        }
    }
}
