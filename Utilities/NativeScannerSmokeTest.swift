//
//  NativeScannerSmokeTest.swift
//  ClamGUI
//
//  Launch-argument smoke test for the native scanner path.
//

import Foundation

@MainActor
enum NativeScannerSmokeTest {
    static let launchArgument = "--clamgui-smoke-test"

    static var isEnabled: Bool {
        CommandLine.arguments.contains(launchArgument)
    }

    static func runAndExit() {
        Task {
            let exitCode = await run()
            Foundation.exit(exitCode)
        }
    }

    private static func run() async -> Int32 {
        print("ClamGUI native scanner smoke test")

        let manager = ClamAVManager.shared
        await manager.checkClamAVInstallation()

        guard manager.isScannerReady else {
            print("FAIL: scanner is not ready: \(manager.scannerStatusMessage)")
            return 2
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clamgui-smoke-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: tempDirectory)
            }

            let cleanFile = tempDirectory.appendingPathComponent("clean.txt")
            let eicarFile = tempDirectory.appendingPathComponent("eicar.com")

            try "ClamGUI scanner smoke test\n".write(to: cleanFile, atomically: true, encoding: .utf8)
            try eicarTestString.write(to: eicarFile, atomically: true, encoding: .ascii)

            let cleanResult = await manager.scanFile(at: cleanFile.path)
            guard cleanResult.status == .clean else {
                print("FAIL: clean file result was \(cleanResult.status)")
                return 3
            }

            let eicarResult = await manager.scanFile(at: eicarFile.path)
            guard eicarResult.status == .infected else {
                print("FAIL: EICAR result was \(eicarResult.status)")
                return 4
            }

            print("PASS: clean file scanned clean")
            print("PASS: EICAR detected as \(eicarResult.threatName ?? "unknown threat")")
            return 0
        } catch {
            print("FAIL: \(error.localizedDescription)")
            return 5
        }
    }

    private static let eicarTestString = #"X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"#
}
