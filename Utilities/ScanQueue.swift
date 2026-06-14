//
//  ScanQueue.swift
//  ClamGUI
//
//  Scan queue item and priority definitions
//

import Foundation

/// Priority levels for scan queue
enum ScanPriority: Int, Comparable {
    case background = 0      // Watchdog automatic scans
    case normal = 1          // Default priority
    case urgent = 2          // Manual user-initiated scans
    
    static func < (lhs: ScanPriority, rhs: ScanPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Represents a file waiting to be scanned
class ScanQueueItem: Identifiable, Equatable {
    let id: UUID
    let filePath: String
    let priority: ScanPriority
    let addedAt: Date
    var scanResult: ClamAVManager.ScanResult?
    var isScanning: Bool = false
    var isCompleted: Bool = false  // Track completion state
    var progress: Double = 0.0
    
    // For manual scans - completion handler
    var completionHandler: ((ClamAVManager.ScanResult) -> Void)?
    
    init(filePath: String, priority: ScanPriority = .normal, completionHandler: ((ClamAVManager.ScanResult) -> Void)? = nil) {
        self.id = UUID()
        self.filePath = filePath
        self.priority = priority
        self.addedAt = Date()
        self.completionHandler = completionHandler
    }
    
    static func == (lhs: ScanQueueItem, rhs: ScanQueueItem) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Thread-safe scan queue
actor ScanQueue {
    static let shared = ScanQueue()
    
    private var queue: [ScanQueueItem] = []
    private var isProcessing: Bool = false
    
    private init() {}
    
    /// Add a file to the scan queue
    func enqueue(_ item: ScanQueueItem) {
        // Insert based on priority (higher priority = earlier in queue)
        var insertIndex = queue.count

        for (index, existingItem) in queue.enumerated() {
            if item.priority > existingItem.priority {
                insertIndex = index
                break
            }
            // If same priority, insert after existing items (FIFO within priority)
            if item.priority == existingItem.priority {
                insertIndex = index + 1
            }
        }

        queue.insert(item, at: insertIndex)
        print("📥 Enqueued: \(item.filePath) (priority: \(item.priority), position: \(insertIndex + 1), hasHandler=\(item.completionHandler != nil))")
    }
    
    /// Get the next item to scan (without removing)
    func peek() -> ScanQueueItem? {
        return queue.first { !$0.isScanning && !$0.isCompleted }
    }

    /// Get and mark the next item as scanning
    func dequeue() -> ScanQueueItem? {
        guard let item = peek() else { return nil }
        item.isScanning = true
        return item
    }

    /// Remove a specific item from the queue
    func remove(_ item: ScanQueueItem) {
        queue.removeAll { $0.id == item.id }
        print("📤 Removed from queue: \(item.filePath)")
    }

    /// Remove a file by path (used when file is deleted)
    func removeByPath(_ filePath: String) {
        queue.removeAll { $0.filePath == filePath }
        print("📤 Removed from queue (by path): \(filePath)")
    }

    /// Mark an item as complete
    func complete(_ item: ScanQueueItem, result: ClamAVManager.ScanResult) {
        print("📋 ScanQueue.complete() called for: \(item.filePath), hasHandler=\(item.completionHandler != nil)")
        
        item.isScanning = false
        item.isCompleted = true  // Mark as completed so it won't be picked up again
        item.scanResult = result
        item.progress = 1.0

        // Call completion handler if present (for manual scans)
        // IMPORTANT: Must be called on main actor for UI updates
        if let handler = item.completionHandler {
            print("📋 Calling completion handler for: \(item.filePath)")
            item.completionHandler = nil  // Clear immediately to avoid retain cycles

            // Ensure callback happens on main actor
            Task { @MainActor in
                print("📋 Executing completion handler on MainActor for: \(item.filePath)")
                handler(result)
            }
        } else {
            print("📋 NO completion handler for: \(item.filePath)")
        }

        // Remove from queue immediately (don't keep completed items)
        remove(item)
    }
    
    /// Update progress for an item
    func updateProgress(_ item: ScanQueueItem, progress: Double) {
        item.progress = progress
    }
    
    /// Get queue statistics
    func getStats() -> (pending: Int, scanning: Int, total: Int) {
        let pending = queue.filter { !$0.isScanning }.count
        let scanning = queue.filter { $0.isScanning }.count
        return (pending, scanning, queue.count)
    }
    
    /// Get all queue items
    func getAllItems() -> [ScanQueueItem] {
        return Array(queue)
    }
    
    /// Check if queue is empty
    func isEmpty() -> Bool {
        return queue.isEmpty
    }
    
    /// Clear all pending items (not scanning)
    func clearPending() {
        queue.removeAll { !$0.isScanning }
        print("🗑️ Cleared all pending items from queue")
    }
}
