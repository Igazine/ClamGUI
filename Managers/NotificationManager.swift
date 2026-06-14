//
//  NotificationManager.swift
//  ClamGUI
//
//  Handles user notifications for scan results and alerts
//

import Foundation
import UserNotifications
import AppKit

/// Manages user notifications for virus alerts and scan results
class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        requestAuthorization()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Window Focus Check

    /// Check if the main app window is currently in focus
    var isAppInFocus: Bool {
        return NSApplication.shared.isActive && NSApplication.shared.keyWindow != nil && NSApplication.shared.keyWindow?.isVisible == true
    }

    // MARK: - Authorization

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Notifications

    /// Show notification when a threat is detected (only if app not in focus)
    func showThreatNotification(fileName: String, threatName: String) {
        // Don't show notification if app is already in focus
        guard !isAppInFocus else {
            print("🔕 Suppressing threat notification (app in focus)")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "🚨 Threat Detected"
        content.body = "\(fileName) contains \(threatName)"
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "default"))
        content.categoryIdentifier = "THREAT_ALERT"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Show notification for scan completion (only if app not in focus)
    func showScanCompleteNotification(fileName: String, isClean: Bool) {
        // Don't show notification if app is already in focus
        guard !isAppInFocus else {
            print("🔕 Suppressing scan notification (app in focus)")
            return
        }
        
        let content = UNMutableNotificationContent()

        if isClean {
            content.title = "✓ Scan Complete"
            content.body = "\(fileName) is clean"
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "default"))
        } else {
            content.title = "⚠️ Scan Complete"
            content.body = "Threats found in \(fileName)"
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "default"))
        }

        content.categoryIdentifier = "SCAN_RESULT"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Show notification for watchdog activity
    func showWatchdogNotification(fileName: String, status: String) {
        // Don't show notification if app is already in focus
        guard !isAppInFocus else {
            print("🔕 Suppressing watchdog notification (app in focus)")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Watchdog Scan"
        content.body = "\(fileName): \(status)"
        content.sound = .none

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Show notification for outdated virus definitions
    func showOutdatedDefinitionsNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Update Available"
        content.body = "Your ClamAV virus definitions may be outdated. Consider running freshclam."
        content.sound = .default
        content.categoryIdentifier = "UPDATE_REMINDER"

        let request = UNNotificationRequest(
            identifier: "outdated_definitions",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Notification Categories
    
    func setupNotificationCategories() {
        let threatAction = UNNotificationAction(
            identifier: "VIEW_THREAT",
            title: "View Details",
            options: .foreground
        )
        
        let threatCategory = UNNotificationCategory(
            identifier: "THREAT_ALERT",
            actions: [threatAction],
            intentIdentifiers: [],
            options: []
        )
        
        let scanAction = UNNotificationAction(
            identifier: "VIEW_SCAN",
            title: "View Results",
            options: .foreground
        )
        
        let scanCategory = UNNotificationCategory(
            identifier: "SCAN_RESULT",
            actions: [scanAction],
            intentIdentifiers: [],
            options: []
        )
        
        let updateAction = UNNotificationAction(
            identifier: "UPDATE_NOW",
            title: "Update",
            options: .foreground
        )
        
        let updateCategory = UNNotificationCategory(
            identifier: "UPDATE_REMINDER",
            actions: [updateAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            threatCategory,
            scanCategory,
            updateCategory
        ])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification actions
        switch response.actionIdentifier {
        case "VIEW_THREAT":
            // Open app to scan results
            break
        case "UPDATE_NOW":
            // Open freshclam instructions
            break
        default:
            break
        }
        
        completionHandler()
    }
}
