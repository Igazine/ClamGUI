//
//  UpdaterManager.swift
//  ClamGUI
//
//  Handles ClamGUI application updates.
//

import AppKit
import CryptoKit
import Foundation

@MainActor
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    @Published var isCheckingForUpdates = false
    @Published var isDownloadingUpdate = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var releaseNotes: String?
    @Published var downloadProgress: Double?
    @Published var statusMessage: String?

    private let githubOwner = "Igazine"
    private let githubRepo = "ClamGUI"
    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    private var packageURL: URL?
    private var checksumURL: URL?

    var canDownloadUpdate: Bool {
        updateAvailable && packageURL != nil && checksumURL != nil
    }

    private init() {}

    func checkForUpdates() async {
        isCheckingForUpdates = true
        statusMessage = nil
        defer { isCheckingForUpdates = false }

        guard let url = URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest") else {
            statusMessage = "The update service URL is invalid."
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClamGUI/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                statusMessage = "Could not retrieve the latest ClamGUI release."
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let cleanVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            latestVersion = cleanVersion
            releaseNotes = release.body
            packageURL = release.assets.first { $0.name == "ClamGUI.pkg" }?.downloadURL
            checksumURL = release.assets.first { $0.name == "ClamGUI.pkg.sha256" }?.downloadURL
            updateAvailable = isVersionNewer(cleanVersion, than: currentVersion)

            if updateAvailable {
                if packageURL == nil || checksumURL == nil {
                    statusMessage = "Version \(cleanVersion) is available, but its PKG or checksum is missing."
                }
            } else {
                statusMessage = "ClamGUI \(currentVersion) is the latest version."
            }
        } catch {
            statusMessage = "Update check failed: \(error.localizedDescription)"
        }
    }

    func downloadAndInstallUpdate() {
        guard !isDownloadingUpdate,
              let latestVersion,
              let packageURL,
              let checksumURL else {
            statusMessage = "The release does not contain a downloadable PKG and checksum."
            return
        }

        Task {
            await downloadAndOpenInstaller(
                version: latestVersion,
                packageURL: packageURL,
                checksumURL: checksumURL
            )
        }
    }

    func showUpdateAlert() {
        guard canDownloadUpdate, let latestVersion else { return }

        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Version \(latestVersion) is now available.\n\n\(releaseNotes ?? "")"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download and Install")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            downloadAndInstallUpdate()
        }
    }

    private func downloadAndOpenInstaller(
        version: String,
        packageURL: URL,
        checksumURL: URL
    ) async {
        isDownloadingUpdate = true
        downloadProgress = 0
        statusMessage = "Downloading ClamGUI \(version)..."
        defer {
            isDownloadingUpdate = false
            downloadProgress = nil
        }

        do {
            let expectedChecksum = try await fetchExpectedChecksum(from: checksumURL)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClamGUI-\(version).pkg")

            let downloader = PackageDownloader()
            let downloadedPackage = try await downloader.download(
                from: packageURL,
                to: destination
            ) { [weak self] progress in
                DispatchQueue.main.async {
                    self?.downloadProgress = progress
                }
            }

            statusMessage = "Verifying downloaded package..."
            let actualChecksum = try sha256(of: downloadedPackage)
            guard actualChecksum.caseInsensitiveCompare(expectedChecksum) == .orderedSame else {
                try? FileManager.default.removeItem(at: downloadedPackage)
                throw UpdaterError.checksumMismatch
            }

            statusMessage = "Opening macOS Installer..."
            guard NSWorkspace.shared.open(downloadedPackage) else {
                throw UpdaterError.couldNotOpenInstaller
            }
            statusMessage = "ClamGUI \(version) is ready in macOS Installer."
        } catch {
            statusMessage = "Update failed: \(error.localizedDescription)"
        }
    }

    private func fetchExpectedChecksum(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("ClamGUI/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let text = String(data: data, encoding: .utf8),
              let checksum = text.split(whereSeparator: \.isWhitespace).first,
              checksum.count == 64,
              checksum.allSatisfy(\.isHexDigit) else {
            throw UpdaterError.invalidChecksum
        }
        return String(checksum)
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func isVersionNewer(_ newVersion: String, than currentVersion: String) -> Bool {
        let newComponents = newVersion.split(separator: ".").compactMap { Int($0) }
        let currentComponents = currentVersion.split(separator: ".").compactMap { Int($0) }

        for index in 0..<max(newComponents.count, currentComponents.count) {
            let newComponent = index < newComponents.count ? newComponents[index] : 0
            let currentComponent = index < currentComponents.count ? currentComponents[index] : 0

            if newComponent != currentComponent {
                return newComponent > currentComponent
            }
        }

        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let downloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
    }
}

private enum UpdaterError: LocalizedError {
    case invalidChecksum
    case checksumMismatch
    case couldNotOpenInstaller

    var errorDescription: String? {
        switch self {
        case .invalidChecksum:
            return "The release checksum is missing or invalid."
        case .checksumMismatch:
            return "The downloaded PKG does not match its published SHA-256 checksum."
        case .couldNotOpenInstaller:
            return "macOS Installer could not open the downloaded PKG."
        }
    }
}

private final class PackageDownloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var progressHandler: ((Double) -> Void)?
    private var session: URLSession?

    func download(
        from source: URL,
        to destination: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        self.destination = destination
        self.progressHandler = progressHandler

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: source).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let destination else { return }

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(with: .success(destination))
        } catch {
            finish(with: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(with: .failure(error))
        }
    }

    private func finish(with result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.finishTasksAndInvalidate()
        session = nil
        continuation.resume(with: result)
    }
}
