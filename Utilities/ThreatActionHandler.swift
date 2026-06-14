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
        
        // Check if we have an auto-action set
        if let action = rememberedAction {
            print("   → Executing remembered action: \(action)")
            await executeAction(action, filePath: filePath, threatName: threatName)
            return
        }

        // Check if settings has auto-action configured
        if SettingsManager.shared.threatAutoAction {
            print("   → Executing settings auto-action: \(SettingsManager.shared.threatAutoActionValue)")
            await executeAction(SettingsManager.shared.threatAutoActionValue, filePath: filePath, threatName: threatName)
            return
        }

        // Suspend queue and show modal
        print("   → Suspending queue and showing modal")
        QueueManager.shared.suspendQueue()
        currentThreat = ThreatInfo(filePath: filePath, threatName: threatName)
        showingThreatModal = true
        print("   → showingThreatModal=\(showingThreatModal)")
        rememberChoice = false
    }
    
    /// User selected an action in the modal
    func userSelectedAction(_ action: ThreatAction) async {
        guard let threat = currentThreat else { return }
        
        // Save choice if requested
        if rememberChoice {
            rememberedActionRaw = action.rawValue
            autoActionEnabled = true
        }
        
        // Execute the action
        await executeAction(action, filePath: threat.filePath, threatName: threat.threatName)
        
        // Close modal and resume queue
        showingThreatModal = false
        currentThreat = nil
        QueueManager.shared.resumeQueue()
    }
    
    /// Execute a threat action
    private func executeAction(_ action: ThreatAction, filePath: String, threatName: String) async {
        // Clear executable bit if setting is enabled
        if SettingsManager.shared.clearExecutableBit {
            await clearExecutableBit(for: filePath)
        }
        
        switch action {
        case .quarantine:
            do {
                try await QuarantineManager.shared.quarantineFile(at: filePath, threatName: threatName)
                print("✅ Quarantined: \(filePath)")
                await updateThreatRecord(filePath: filePath, action: "quarantined")
            } catch {
                print("⚠️ Failed to quarantine: \(error.localizedDescription)")
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
            var attributes = try fileManager.attributesOfItem(atPath: filePath)
            if let permissions = attributes[.posixPermissions] as? NSNumber {
                // Remove execute bits (mask out 0o111)
                var newPermissions = permissions.intValue & ~0o111
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
    let detectedAt = Date()
    
    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
    
    var folderPath: String {
        URL(fileURLWithPath: filePath).deletingLastPathComponent().path
    }
}
