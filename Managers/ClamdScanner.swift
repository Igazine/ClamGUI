//
//  ClamdScanner.swift
//  ClamGUI
//
//  Legacy scanner backend that talks to clamd through QueueManager.
//

import Foundation

struct ClamdScanner: MalwareScanner {
    let backend: ScannerBackend = .clamd

    func prepare() async throws {
        QueueManager.shared.start()
    }

    func scanFile(at path: String) async -> ClamAVManager.ScanResult {
        await QueueManager.shared.scanFile(at: path)
    }

    func reloadSignatures() async throws {
        QueueManager.shared.enqueueControlCommand(type: .reload)
    }

    func shutdown() async {
        QueueManager.shared.stopProcessing()
    }
}
