//
//  LibClamAVScanner.swift
//  ClamGUI
//
//  Native in-process scanner backed by libclamav.
//

import Darwin
import Foundation

actor LibClamAVScanner: MalwareScanner {
    let backend: ScannerBackend = .nativeLibClamAV

    private struct API {
        let handle: UnsafeMutableRawPointer
        let clInit: @convention(c) (UInt32) -> Int32
        let clEngineNew: @convention(c) () -> OpaquePointer?
        let clLoad: @convention(c) (UnsafePointer<CChar>?, OpaquePointer?, UnsafeMutablePointer<UInt32>?, UInt32) -> Int32
        let clEngineCompile: @convention(c) (OpaquePointer?) -> Int32
        let clEngineFree: @convention(c) (OpaquePointer?) -> Int32
        let clScanFileEx: @convention(c) (
            UnsafePointer<CChar>,
            UnsafeMutablePointer<Int32>?,
            UnsafeMutablePointer<UnsafePointer<CChar>?>?,
            UnsafeMutablePointer<UInt64>?,
            OpaquePointer?,
            UnsafeMutableRawPointer?,
            UnsafeMutableRawPointer?,
            UnsafePointer<CChar>?,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
            UnsafePointer<CChar>?,
            UnsafePointer<CChar>?,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        ) -> Int32
        let clStrError: @convention(c) (Int32) -> UnsafePointer<CChar>?
        let clRetDbDir: @convention(c) () -> UnsafePointer<CChar>?
    }

    private var api: API?
    private var engine: OpaquePointer?
    private var signatureCount: UInt32 = 0
    private var databasePath: String?

    func prepare() async throws {
        if engine != nil {
            return
        }

        let api = try loadAPI()
        let initResult = api.clInit(LibClamAVConstants.initDefault)
        guard initResult == LibClamAVConstants.success else {
            throw MalwareScannerError.initializationFailed("libclamav initialization failed: \(errorMessage(initResult, api: api))")
        }

        guard let newEngine = api.clEngineNew() else {
            throw MalwareScannerError.initializationFailed("libclamav could not create a scan engine.")
        }

        do {
            let dbPath = try resolveDatabasePath(api: api)
            var loadedSignatures: UInt32 = 0
            let loadResult = dbPath.withCString { pathPointer in
                api.clLoad(pathPointer, newEngine, &loadedSignatures, LibClamAVConstants.dbStandardOptions)
            }

            guard loadResult == LibClamAVConstants.success else {
                _ = api.clEngineFree(newEngine)
                throw MalwareScannerError.signatureLoadFailed("Could not load ClamAV signatures from \(dbPath): \(errorMessage(loadResult, api: api))")
            }

            let compileResult = api.clEngineCompile(newEngine)
            guard compileResult == LibClamAVConstants.success else {
                _ = api.clEngineFree(newEngine)
                throw MalwareScannerError.engineCompileFailed("Could not compile ClamAV engine: \(errorMessage(compileResult, api: api))")
            }

            self.api = api
            self.engine = newEngine
            self.signatureCount = loadedSignatures
            self.databasePath = dbPath
        } catch {
            _ = api.clEngineFree(newEngine)
            throw error
        }
    }

    func scanFile(at path: String) async -> ClamAVManager.ScanResult {
        guard let api, let engine else {
            return ClamAVManager.ScanResult(filePath: path, status: .error, threatName: "Native scanner is not prepared", timestamp: Date())
        }

        var virusNamePointer: UnsafePointer<CChar>?
        var verdict: Int32 = LibClamAVConstants.verdictNothingFound
        var scanned: UInt64 = 0
        var options = LibClamAVScanOptions.default

        let result = path.withCString { pathPointer in
            withUnsafeMutablePointer(to: &options) { optionsPointer in
                api.clScanFileEx(
                    pathPointer,
                    &verdict,
                    &virusNamePointer,
                    &scanned,
                    engine,
                    UnsafeMutableRawPointer(optionsPointer),
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil
                )
            }
        }

        switch verdict {
        case LibClamAVConstants.verdictNothingFound,
             LibClamAVConstants.verdictTrusted:
            return ClamAVManager.ScanResult(filePath: path, status: .clean, threatName: nil, timestamp: Date())
        case LibClamAVConstants.verdictStrongIndicator,
             LibClamAVConstants.verdictPotentiallyUnwanted:
            let threatName = virusNamePointer.map { String(cString: $0) } ?? "Unknown"
            return ClamAVManager.ScanResult(filePath: path, status: .infected, threatName: threatName, timestamp: Date())
        default:
            break
        }

        if result == LibClamAVConstants.success {
            return ClamAVManager.ScanResult(filePath: path, status: .clean, threatName: nil, timestamp: Date())
        } else {
            return ClamAVManager.ScanResult(filePath: path, status: .error, threatName: errorMessage(result, api: api), timestamp: Date())
        }
    }

    func reloadSignatures() async throws {
        if let engine {
            _ = api?.clEngineFree(engine)
        }
        engine = nil
        signatureCount = 0
        databasePath = nil
        try await prepare()
    }

    func shutdown() async {
        if let engine {
            _ = api?.clEngineFree(engine)
        }
        if let handle = api?.handle {
            dlclose(handle)
        }
        api = nil
        engine = nil
        signatureCount = 0
        databasePath = nil
    }

    private func loadAPI() throws -> API {
        if let api {
            return api
        }

        let handle = try openLibrary()

        return API(
            handle: handle,
            clInit: try symbol("cl_init", in: handle),
            clEngineNew: try symbol("cl_engine_new", in: handle),
            clLoad: try symbol("cl_load", in: handle),
            clEngineCompile: try symbol("cl_engine_compile", in: handle),
            clEngineFree: try symbol("cl_engine_free", in: handle),
            clScanFileEx: try symbol("cl_scanfile_ex", in: handle),
            clStrError: try symbol("cl_strerror", in: handle),
            clRetDbDir: try symbol("cl_retdbdir", in: handle)
        )
    }

    private func openLibrary() throws -> UnsafeMutableRawPointer {
        let bundledPaths = bundledLibrarySearchPaths()
        let existingBundledPaths = bundledPaths.filter { FileManager.default.fileExists(atPath: $0) }

        for path in existingBundledPaths {
            if let handle = openLibrary(at: path) {
                return handle
            }
        }

        if !existingBundledPaths.isEmpty {
            let message = dlerror().map { String(cString: $0) } ?? "unknown dynamic loader error"
            throw MalwareScannerError.unavailable("Bundled libclamav could not be loaded: \(message)")
        }

        for path in developmentLibrarySearchPaths() {
            if let handle = openLibrary(at: path) {
                return handle
            }
        }

        let message = dlerror().map { String(cString: $0) } ?? "libclamav was not found in the app bundle or development paths"
        throw MalwareScannerError.unavailable("Could not load libclamav: \(message)")
    }

    private func openLibrary(at path: String) -> UnsafeMutableRawPointer? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        return dlopen(path, RTLD_NOW | RTLD_LOCAL)
    }

    private func bundledLibrarySearchPaths() -> [String] {
        if let privateFrameworksPath = Bundle.main.privateFrameworksPath {
            return [
                URL(fileURLWithPath: privateFrameworksPath).appendingPathComponent("libclamav.12.dylib").path,
                URL(fileURLWithPath: privateFrameworksPath).appendingPathComponent("libclamav.dylib").path
            ]
        }

        return []
    }

    private func developmentLibrarySearchPaths() -> [String] {
        [
            "/opt/homebrew/lib/libclamav.12.dylib",
            "/opt/homebrew/lib/libclamav.dylib",
            "/usr/local/lib/libclamav.12.dylib",
            "/usr/local/lib/libclamav.dylib"
        ]
    }

    private func resolveDatabasePath(api: API) throws -> String {
        let appDatabasePath = Self.appDatabaseDirectory.path
        if Self.directoryContainsDatabase(appDatabasePath) {
            return appDatabasePath
        }

        if let defaultPathPointer = api.clRetDbDir() {
            let defaultPath = String(cString: defaultPathPointer)
            if Self.directoryContainsDatabase(defaultPath) {
                return defaultPath
            }
        }

        throw MalwareScannerError.signatureLoadFailed("No ClamAV signature database found. Expected databases in \(appDatabasePath).")
    }

    private static var appDatabaseDirectory: URL {
        SignatureDatabaseManager.databaseDirectory
    }

    private static func directoryContainsDatabase(_ path: String) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return false
        }

        return contents.contains { fileName in
            fileName.hasSuffix(".cvd") || fileName.hasSuffix(".cld") || fileName.hasSuffix(".cud")
        }
    }

    private func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer) throws -> T {
        guard let pointer = dlsym(handle, name) else {
            throw MalwareScannerError.unavailable("libclamav is missing required symbol: \(name)")
        }

        return unsafeBitCast(pointer, to: T.self)
    }

    private func errorMessage(_ code: Int32, api: API) -> String {
        if let pointer = api.clStrError(code) {
            return String(cString: pointer)
        }
        return "libclamav error \(code)"
    }
}

private enum LibClamAVConstants {
    static let success: Int32 = 0
    static let initDefault: UInt32 = 0
    static let dbStandardOptions: UInt32 = 0x2 | 0x8 | 0x2000
    static let verdictNothingFound: Int32 = 0
    static let verdictTrusted: Int32 = 1
    static let verdictStrongIndicator: Int32 = 2
    static let verdictPotentiallyUnwanted: Int32 = 3
}

private struct LibClamAVScanOptions {
    var general: UInt32
    var parse: UInt32
    var heuristic: UInt32
    var mail: UInt32
    var dev: UInt32

    static var `default`: LibClamAVScanOptions {
        LibClamAVScanOptions(
            general: 0x4,
            parse: UInt32.max,
            heuristic: 0,
            mail: 0,
            dev: 0
        )
    }
}
