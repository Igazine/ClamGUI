//
//  SignatureDatabaseManager.swift
//  ClamGUI
//
//  Manages ClamGUI-owned ClamAV signature databases.
//

import Foundation

struct SignatureDatabaseStatus {
    let databaseDirectory: URL
    let databaseFiles: [URL]
    let newestModificationDate: Date?
    let isOutdated: Bool

    var signatureCount: Int {
        databaseFiles.count
    }

    var versionDescription: String {
        guard !databaseFiles.isEmpty else {
            return "Not installed"
        }

        if let newestModificationDate {
            return "\(databaseFiles.count) database files, updated \(newestModificationDate.formatted(date: .abbreviated, time: .shortened))"
        }

        return "\(databaseFiles.count) database files"
    }
}

struct SignatureUpdateResult {
    let output: String
    let status: SignatureDatabaseStatus
}

actor SignatureDatabaseManager {
    static let shared = SignatureDatabaseManager()

    static var supportDirectory: URL {
        let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        return URL(fileURLWithPath: homeDir)
            .appendingPathComponent("Library/Application Support/ClamGUI")
    }

    static var databaseDirectory: URL {
        supportDirectory.appendingPathComponent("Database")
    }

    private var configURL: URL {
        Self.supportDirectory.appendingPathComponent("freshclam.conf")
    }

    private var logURL: URL {
        Self.supportDirectory.appendingPathComponent("freshclam.log")
    }

    private init() {}

    func status() async -> SignatureDatabaseStatus {
        let databaseDirectory = Self.databaseDirectory
        let files = databaseFiles(in: databaseDirectory)
        let newestDate = files.compactMap { url -> Date? in
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        }.max()

        let isOutdated: Bool
        if let newestDate {
            isOutdated = Date().timeIntervalSince(newestDate) > 2 * 24 * 60 * 60
        } else {
            isOutdated = true
        }

        return SignatureDatabaseStatus(
            databaseDirectory: databaseDirectory,
            databaseFiles: files,
            newestModificationDate: newestDate,
            isOutdated: isOutdated
        )
    }

    func updateDefinitions() async throws -> SignatureUpdateResult {
        try ensureDirectories()
        try writeFreshclamConfig()

        guard let freshclamURL = findFreshclam() else {
            throw MalwareScannerError.unavailable("freshclam was not found. Bundle freshclam with ClamGUI or install ClamAV for development.")
        }

        let output = try await runFreshclam(freshclamURL: freshclamURL)
        let currentStatus = await status()
        return SignatureUpdateResult(output: output, status: currentStatus)
    }

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(
            at: Self.supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        try FileManager.default.createDirectory(
            at: Self.databaseDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func writeFreshclamConfig() throws {
        let config = """
        DatabaseDirectory \(Self.databaseDirectory.path)
        UpdateLogFile \(logURL.path)
        LogTime yes
        DatabaseMirror database.clamav.net
        ScriptedUpdates yes
        CompressLocalDatabase no
        Bytecode yes
        """

        try config.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func findFreshclam() -> URL? {
        var candidates: [URL] = []

        if let executableURL = Bundle.main.executableURL {
            candidates.append(executableURL.deletingLastPathComponent().appendingPathComponent("freshclam"))
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("freshclam"))
        }

        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/freshclam"),
            URL(fileURLWithPath: "/usr/local/bin/freshclam")
        ])

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func runFreshclam(freshclamURL: URL) async throws -> String {
        let process = Process()
        process.executableURL = freshclamURL
        process.arguments = [
            "--config-file=\(configURL.path)",
            "--foreground",
            "--stdout"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: MalwareScannerError.signatureLoadFailed(output.isEmpty ? "freshclam failed with exit code \(process.terminationStatus)" : output))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func databaseFiles(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { ["cvd", "cld", "cud"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
