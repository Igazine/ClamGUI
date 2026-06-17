//
//  ScanResultsDatabase.swift
//  ClamGUI
//
//  Single-table database for all scan results
//

import Foundation
import SQLite3

/// Database configuration
struct DatabaseConfig {
    static let maxRecordsPerFolder: Int = 500_000
    static let retentionDays: Int = 90
    static let cleanupThreshold: Int = 450_000
    static let vacuumIntervalDays: Int = 7
    static let filesystemCheckIntervalDays: Int = 7
}

/// Scan result status
enum ScanStatus: String {
    case clean
    case infected
    case skippedTooLarge
    case error
}

/// A scan result record
struct ScanResultRecord {
    let id: Int64
    let path: String
    let folderId: Int64
    let status: ScanStatus
    let threatName: String?
    let scanTimestamp: Date
    let fileSize: Int64
    let modificationDate: Date
    
    var fileName: String { URL(fileURLWithPath: path).lastPathComponent }
    var folderPath: String { URL(fileURLWithPath: path).deletingLastPathComponent().path }
}

/// Single-table scan results database
class ScanResultsDatabase: @unchecked Sendable {
    static let shared = ScanResultsDatabase()
    
    private var db: OpaquePointer?
    private let dbPath: String
    private let dbQueue = DispatchQueue(label: "com.clamgui.db")
    private let dbLock = NSLock()
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    private init() {
        let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let dbDir = URL(fileURLWithPath: homeDir)
            .appendingPathComponent("Library/Application Support/ClamGUI")
        
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        
        dbPath = dbDir.appendingPathComponent("scan_results.db").path
        openDatabase()
    }
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("❌ Failed to open database at: \(dbPath)")
            return
        }
        
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA busy_timeout=5000;", nil, nil, nil)
        
        createTables()
    }
    
    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS scan_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL,
            folder_id INTEGER NOT NULL,
            status TEXT NOT NULL,
            threat_name TEXT,
            scan_timestamp INTEGER NOT NULL,
            file_size INTEGER NOT NULL,
            modification_date INTEGER NOT NULL,
            UNIQUE(path, folder_id)
        );
        
        CREATE INDEX IF NOT EXISTS idx_scan_results_folder ON scan_results(folder_id);
        CREATE INDEX IF NOT EXISTS idx_scan_results_status ON scan_results(status);
        CREATE INDEX IF NOT EXISTS idx_scan_results_path ON scan_results(path);
        """
        
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            print("❌ Error creating tables: \(String(cString: errMsg!))")
            sqlite3_free(errMsg)
        }
    }
    
    // MARK: - Public API
    
    /// Record or update a scan result
    func recordScan(path: String, folderId: Int64, status: ScanStatus, threatName: String? = nil) async {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        guard attrs != nil || status == .infected else {
            return
        }

        let fileSize = attrs?[.size] as? Int64 ?? 0
        let modDate = Int64((attrs?[.modificationDate] as? Date ?? Date()).timeIntervalSince1970)
        let scanTimestamp = Int64(Date().timeIntervalSince1970)
        
        recordScanSync(path: path, folderId: folderId, status: status,
                      threatName: threatName, scanTimestamp: scanTimestamp,
                      fileSize: fileSize, modificationDate: modDate)
    }
    
    /// Check if a file needs scanning
    func needsScan(_ path: String, folderId: Int64) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            return true
        }
        
        let currentModDate = Int64((attrs[.modificationDate] as? Date ?? Date()).timeIntervalSince1970)
        let currentSize = attrs[.size] as? Int64 ?? 0
        
        guard let record = getRecord(path, folderId: folderId) else {
            return true
        }
        
        let storedModDate = Int64(record.modificationDate.timeIntervalSince1970)
        let modDateChanged = abs(storedModDate - currentModDate) > 2
        let sizeChanged = record.fileSize != currentSize
        
        return modDateChanged || sizeChanged
    }
    
    /// Get all infected files for a folder
    func getInfectedFiles(folderId: Int64) -> [ScanResultRecord] {
        dbLock.lock()
        defer { dbLock.unlock() }

        let sql = """
        SELECT id, path, folder_id, status, threat_name, scan_timestamp, file_size, modification_date
        FROM scan_results
        WHERE folder_id = ? AND status = 'infected'
        ORDER BY scan_timestamp DESC
        """
        
        var statement: OpaquePointer?
        var results: [ScanResultRecord] = []
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("⚠️ getInfectedFiles: Prepare failed")
            return []
        }
        
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, folderId)
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let path = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "NULL"
            let statusStr = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "NULL"
            let threat = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? "NULL"
            
            let record = ScanResultRecord(
                id: id,
                path: path,
                folderId: sqlite3_column_int64(statement, 2),
                status: ScanStatus(rawValue: statusStr) ?? .error,
                threatName: threat == "NULL" ? nil : threat,
                scanTimestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_double(statement, 5))),
                fileSize: sqlite3_column_int64(statement, 6),
                modificationDate: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_double(statement, 7)))
            )
            if record.status == .infected {
                results.append(record)
            }
        }
        
        return results
    }
    
    /// Get total record count for a folder
    func getRecordCount(folderId: Int64) -> Int {
        dbLock.lock()
        defer { dbLock.unlock() }

        let sql = "SELECT COUNT(*) FROM scan_results WHERE folder_id = ?"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, folderId)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }
        
        return 0
    }
    
    /// Remove a record (user deleted file)
    func removeRecord(path: String, folderId: Int64) async {
        removeRecordSync(path: path, folderId: folderId)
    }

    private func removeRecordSync(path: String, folderId: Int64) {
        dbLock.lock()
        defer { dbLock.unlock() }

        let sql = "DELETE FROM scan_results WHERE folder_id = ? AND path = ?"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, folderId)
        bindText(statement, index: 2, value: path)
        
        sqlite3_step(statement)
    }

    /// Remove a record only when it is not an infected finding.
    func removeNonThreatRecord(path: String, folderId: Int64) async {
        if getRecord(path, folderId: folderId)?.status == .infected {
            return
        }

        await removeRecord(path: path, folderId: folderId)
    }
    
    /// Clear all records (for testing)
    func clearAll() async {
        clearAllSync()
    }

    private func clearAllSync() {
        dbLock.lock()
        defer { dbLock.unlock() }

        sqlite3_exec(db, "DELETE FROM scan_results", nil, nil, nil)
    }
    
    // MARK: - Private Helpers
    
    private func recordScanSync(path: String, folderId: Int64, status: ScanStatus,
                               threatName: String?, scanTimestamp: Int64,
                               fileSize: Int64, modificationDate: Int64) {
        dbLock.lock()
        defer { dbLock.unlock() }

        print("💾 recordScanSync: path=\(path), folderId=\(folderId), status=\(status.rawValue)")
        
        let sql = """
        INSERT INTO scan_results (path, folder_id, status, threat_name, scan_timestamp, file_size, modification_date)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(path, folder_id) DO UPDATE SET
            status = excluded.status,
            threat_name = excluded.threat_name,
            scan_timestamp = excluded.scan_timestamp,
            file_size = excluded.file_size,
            modification_date = excluded.modification_date
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            print("❌ Error preparing statement: \(String(cString: sqlite3_errmsg(db)!))")
            return
        }
        
        defer { sqlite3_finalize(statement) }
        
        bindText(statement, index: 1, value: path)
        sqlite3_bind_int64(statement, 2, folderId)
        switch status {
        case .clean: bindText(statement, index: 3, value: "clean")
        case .infected: bindText(statement, index: 3, value: "infected")
        case .skippedTooLarge: bindText(statement, index: 3, value: "skippedTooLarge")
        case .error: bindText(statement, index: 3, value: "error")
        }
        
        if let threatName = threatName {
            bindText(statement, index: 4, value: threatName)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        
        sqlite3_bind_int64(statement, 5, scanTimestamp)
        sqlite3_bind_int64(statement, 6, fileSize)
        sqlite3_bind_int64(statement, 7, modificationDate)
        
        let stepResult = sqlite3_step(statement)
        if stepResult != SQLITE_DONE {
            print("❌ Error recording scan: \(String(cString: sqlite3_errmsg(db)!)) (step=\(stepResult))")
        } else {
            print("✅ recordScanSync: Successfully recorded/updated \(path)")
        }
    }
    
    func getRecord(_ path: String, folderId: Int64) -> ScanResultRecord? {
        dbLock.lock()
        defer { dbLock.unlock() }

        let sql = """
        SELECT id, path, folder_id, status, threat_name, scan_timestamp, file_size, modification_date
        FROM scan_results
        WHERE folder_id = ? AND path = ?
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int64(statement, 1, folderId)
        bindText(statement, index: 2, value: path)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return ScanResultRecord(
                id: sqlite3_column_int64(statement, 0),
                path: String(cString: sqlite3_column_text(statement, 1)),
                folderId: sqlite3_column_int64(statement, 2),
                status: ScanStatus(rawValue: String(cString: sqlite3_column_text(statement, 3))) ?? .error,
                threatName: sqlite3_column_text(statement, 4).map { String(cString: $0) },
                scanTimestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_double(statement, 5))),
                fileSize: sqlite3_column_int64(statement, 6),
                modificationDate: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_double(statement, 7)))
            )
        }
        
        return nil
    }

    private func bindText(_ statement: OpaquePointer?, index: Int32, value: String) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }
}
