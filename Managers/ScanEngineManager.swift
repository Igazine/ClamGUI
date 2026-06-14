//
//  ScanEngineManager.swift
//  ClamGUI
//
//  Selects and owns the active malware scanner backend.
//

import Foundation

actor ScanEngineManager {
    static let shared = ScanEngineManager()

    private let nativeScanner = LibClamAVScanner()
    private let clamdScanner = ClamdScanner()
    private var activeScanner: MalwareScanner?
    private var lastNativeError: String?

    private init() {}

    func preparePreferredScanner(clamdSocketExists: Bool) async -> ScannerPreparationStatus {
        do {
            try await nativeScanner.prepare()
            activeScanner = nativeScanner
            lastNativeError = nil
            return ScannerPreparationStatus(
                isReady: true,
                backend: .nativeLibClamAV,
                message: "Native libclamav scanner ready"
            )
        } catch {
            lastNativeError = error.localizedDescription
        }

        if clamdSocketExists {
            do {
                try await clamdScanner.prepare()
                activeScanner = clamdScanner
                return ScannerPreparationStatus(
                    isReady: true,
                    backend: .clamd,
                    message: "Legacy clamd scanner ready"
                )
            } catch {
                return ScannerPreparationStatus(
                    isReady: false,
                    backend: nil,
                    message: error.localizedDescription
                )
            }
        }

        activeScanner = nil
        return ScannerPreparationStatus(
            isReady: false,
            backend: nil,
            message: lastNativeError ?? "No scanner backend is ready"
        )
    }

    func useLegacyClamdScanner() async throws {
        try await clamdScanner.prepare()
        activeScanner = clamdScanner
    }

    func scanFile(at path: String) async -> ClamAVManager.ScanResult {
        guard let activeScanner else {
            return ClamAVManager.ScanResult(filePath: path, status: .error, threatName: "No scanner backend is ready", timestamp: Date())
        }

        return await activeScanner.scanFile(at: path)
    }

    func reloadSignatures() async throws {
        guard let activeScanner else {
            throw MalwareScannerError.unavailable("No scanner backend is ready")
        }

        try await activeScanner.reloadSignatures()
    }

    func shutdown() async {
        await activeScanner?.shutdown()
        activeScanner = nil
    }

    func activeBackend() async -> ScannerBackend? {
        activeScanner?.backend
    }
}
