//
//  QueueCommand.swift
//  ClamGUI
//
//  Defines commands for the QueueManager
//

import Foundation

/// Priority levels for queue commands
/// Lower integer value = Higher priority (processed first)
enum CommandPriority: Int, Comparable {
    case highest = 0  // SHUTDOWN
    case high = 1     // RELOAD, STATS, VERSION
    case normal = 2   // Manual Scan
    case low = 3      // Watchdog Scan

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Represents an action to be executed by the queue
protocol QueueCommand: Sendable {
    var id: UUID { get }
    var priority: CommandPriority { get }
    var description: String { get }
}

/// Specific commands
struct ScanCommand: QueueCommand {
    let id: UUID = UUID()
    let priority: CommandPriority
    let filePath: String
    let completion: @Sendable (ClamAVManager.ScanResult) -> Void

    var description: String { "SCAN \(filePath)" }
}

struct ControlCommand: QueueCommand {
    enum CommandType {
        case shutdown
        case reload
        case stats
        case version
        case ping
    }

    let id: UUID = UUID()
    let priority: CommandPriority
    let type: CommandType
    let completion: (@Sendable (String) -> Void)?

    var description: String {
        switch type {
        case .shutdown: return "SHUTDOWN"
        case .reload: return "RELOAD"
        case .stats: return "STATS"
        case .version: return "VERSION"
        case .ping: return "PING"
        }
    }
}

/// Status of the queue for UI display
enum ScanQueueStatus: String {
    case idle
    case scanning
    case suspended
}
