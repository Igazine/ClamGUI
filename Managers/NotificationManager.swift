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

    private enum UserInfoKey {
        static let presentIfForeground = "presentIfForeground"
    }

    private let notificationCenter = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        notificationCenter.delegate = self
        setupNotificationCategories()
        requestAuthorization()
    }

    // MARK: - Window Focus Check

    /// Check if ClamGUI is the active foreground app.
    var isAppInForeground: Bool {
        if Thread.isMainThread {
            return NSApplication.shared.isActive
        }

        return DispatchQueue.main.sync {
            NSApplication.shared.isActive
        }
    }

    // MARK: - Authorization

    func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            } else if !granted {
                print("Notification authorization was not granted")
            }
        }
    }

    // MARK: - Notifications

    /// Show notification when a threat is detected (only if app not in focus)
    func showThreatNotification(fileName: String, threatName: String) {
        guard !isAppInForeground else {
            print("Suppressing threat notification because ClamGUI is in the foreground")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Threat Detected"
        content.body = "\(fileName) contains \(threatName)"
        content.sound = .default
        content.categoryIdentifier = "THREAT_ALERT"
        content.userInfo = [UserInfoKey.presentIfForeground: true]

        requestAttention()
        deliverThreatNotification(content)
    }

    /// Show notification for scan completion (only if app not in focus)
    func showScanCompleteNotification(fileName: String, isClean: Bool) {
        guard !isAppInForeground else {
            print("Suppressing scan notification because ClamGUI is in the foreground")
            return
        }
        
        let content = UNMutableNotificationContent()

        if isClean {
            content.title = "✓ Scan Complete"
            content.body = "\(fileName) is clean"
            content.sound = .default
        } else {
            content.title = "⚠️ Scan Complete"
            content.body = "Threats found in \(fileName)"
            content.sound = .default
        }

        content.categoryIdentifier = "SCAN_RESULT"
        content.userInfo = [UserInfoKey.presentIfForeground: true]

        deliver(content)
    }

    /// Show notification for watchdog activity
    func showWatchdogNotification(fileName: String, status: String) {
        guard !isAppInForeground else {
            print("Suppressing watchdog notification because ClamGUI is in the foreground")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Watchdog Scan"
        content.body = "\(fileName): \(status)"
        content.sound = .none
        content.userInfo = [UserInfoKey.presentIfForeground: true]

        deliver(content)
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

        notificationCenter.add(request) { error in
            if let error {
                print("Failed to schedule outdated definitions notification: \(error.localizedDescription)")
            }
        }
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
        
        notificationCenter.setNotificationCategories([
            threatCategory,
            scanCategory,
            updateCategory
        ])
    }

    private func deliver(_ content: UNNotificationContent) {
        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else { return }

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.add(content)
            case .notDetermined:
                self.notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        print("Notification authorization error: \(error.localizedDescription)")
                    }

                    guard granted else {
                        print("Notification authorization was not granted")
                        return
                    }

                    self.add(content)
                }
            case .denied:
                print("Notification not delivered because authorization is denied")
            @unknown default:
                print("Notification not delivered because authorization status is unknown")
            }
        }
    }

    private func add(_ content: UNNotificationContent) {
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        notificationCenter.add(request) { error in
            if let error {
                print("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }

    private func deliverThreatNotification(_ content: UNNotificationContent) {
        let notification = NSUserNotification()
        notification.title = content.title
        notification.informativeText = content.body
        notification.soundName = NSUserNotificationDefaultSoundName
        notification.hasActionButton = true
        notification.actionButtonTitle = "View"
        notification.otherButtonTitle = "Dismiss"

        NSUserNotificationCenter.default.delegate = self
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func requestAttention() {
        DispatchQueue.main.async {
            NSApplication.shared.requestUserAttention(.criticalRequest)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.content.userInfo[NotificationManager.UserInfoKey.presentIfForeground] as? Bool == true {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([])
        }
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

extension NotificationManager: NSUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        !isAppInForeground
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
