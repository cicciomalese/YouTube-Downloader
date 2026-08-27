//
//  YtdlpUpdater.swift
//  YouTubeDownloader
//

import Foundation
import Combine

@MainActor
class YtdlpUpdater: ObservableObject {
    
    @Published var isChecking = false
    @Published var isUpdating = false
    @Published var updateAvailable = false
    @Published var currentVersion: String?
    @Published var latestVersion: String?
    @Published var updateProgress: Double = 0
    @Published var statusMessage: String = ""
    
    private let githubAPI = "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
    
    // Fetch the latest published version from GitHub. This has no
    // dependency on the locally installed yt-dlp, so callers should fire
    // it concurrently with local dependency resolution (e.g. via `async
    // let`) rather than waiting for that to finish first.
    func fetchLatestVersion() async -> String? {
        isChecking = true
        defer { isChecking = false }
        
        do {
            let latest = try await getLatestVersion()
            print("🌐 Latest version: \(latest)")
            return latest
        } catch {
            print("❌ Update check error: \(error)")
            return nil
        }
    }
    
    // Combine an already-known local version (from DependencyChecker,
    // which already ran `--version` to verify the binary works) with an
    // already-fetched latest version, and update published state. No
    // process spawning or network calls happen here — just comparison.
    func applyUpdateCheck(currentVersion: String?, latestVersion: String?) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        
        guard let currentVersion else {
            statusMessage = "yt-dlp not found"
            return
        }
        
        guard let latestVersion else {
            statusMessage = "Update check failed"
            return
        }
        
        updateAvailable = isNewerVersion(latest: latestVersion, current: currentVersion)
        statusMessage = updateAvailable
            ? "Update available: \(latestVersion) (current: \(currentVersion))"
            : "yt-dlp is up to date (\(currentVersion))"
    }
    
    // Download and install latest yt-dlp
    func updateYtdlp() async {
        guard !isUpdating else { return }
        
        print("🚀 Starting yt-dlp update process...")
        isUpdating = true
        updateProgress = 0
        statusMessage = "Downloading yt-dlp update..."
        defer { isUpdating = false }
        
        do {
            // Download binary
            let downloadURL = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
            print("🌐 Downloading from: \(downloadURL)")
            
            let startTime = Date()
            let binaryData = try await downloadWithProgress(from: downloadURL)
            let downloadTime = Date().timeIntervalSince(startTime)
            print("⏱️  Download completed in \(String(format: "%.2f", downloadTime)) seconds")
            
            statusMessage = "Installing binary..."
            updateProgress = 0.85
            print("📦 Installing binary...")
            
            // Get bundle path
            guard let bundlePath = Bundle.main.resourcePath else {
                throw UpdateError.installFailed("Cannot access app bundle")
            }
            
            let ytdlpPath = "\(bundlePath)/yt-dlp"
            let backupPath = "\(bundlePath)/yt-dlp.backup"
            
            print("📍 Install path: \(ytdlpPath)")
            
            // Backup current binary
            if FileManager.default.fileExists(atPath: ytdlpPath) {
                statusMessage = "Creating backup..."
                print("💾 Creating backup...")
                try? FileManager.default.removeItem(atPath: backupPath)
                try FileManager.default.copyItem(atPath: ytdlpPath, toPath: backupPath)
            }
            
            // Write new binary
            statusMessage = "Writing new binary..."
            updateProgress = 0.9
            print("✍️  Writing new binary...")
            try binaryData.write(to: URL(fileURLWithPath: ytdlpPath))
            
            // Make executable
            statusMessage = "Setting executable permissions..."
            updateProgress = 0.95
            print("🔧 Setting executable permissions...")
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: ytdlpPath
            )
            
            // Verify installation
            statusMessage = "Verifying installation..."
            print("🔍 Verifying installation...")
            let newVersion = try await getCurrentVersion()
            
            updateProgress = 1.0
            currentVersion = newVersion
            updateAvailable = false
            statusMessage = "Updated to yt-dlp \(newVersion ?? "latest")"
            
            print("✅ Update successful! New version: \(newVersion ?? "unknown")")
            
            // Remove backup after successful update
            try? FileManager.default.removeItem(atPath: backupPath)
            
        } catch {
            statusMessage = "Update failed: \(error.localizedDescription)"
            print("Update error: \(error)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func getCurrentVersion() async throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: BundleHelpers.ytdlpPath)
        process.arguments = ["--version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try process.run()
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func getLatestVersion() async throws -> String {
        guard let url = URL(string: githubAPI) else {
            throw UpdateError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.networkError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            throw UpdateError.invalidResponse
        }
        
        return tagName
    }
    
    private func downloadWithProgress(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidURL
        }
        
        // Use temp file for curl download
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("yt-dlp-download-\(UUID().uuidString)")
        
        print("📥 Starting curl download from: \(urlString)")
        print("📁 Temp file: \(tempFile.path)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "-L",  // Follow redirects
            "-#",  // Progress bar
            "-o", tempFile.path,
            urlString
        ]
        
        let pipe = Pipe()
        process.standardError = pipe  // curl outputs progress to stderr
        
        // Track progress from curl output
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            
            // Parse curl progress (format: ######## 45.2%)
            if let percentMatch = output.range(of: #"(\d+\.\d+)%"#, options: .regularExpression) {
                let percentString = output[percentMatch].replacingOccurrences(of: "%", with: "")
                if let percent = Double(percentString) {
                    Task { @MainActor in
                        self.updateProgress = (percent / 100.0) * 0.8  // 0-80% for download
                        print("📊 Download progress: \(String(format: "%.1f", percent))%")
                    }
                }
            }
        }
        
        try process.run()
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }
        
        handle.readabilityHandler = nil
        
        guard process.terminationStatus == 0 else {
            print("❌ curl failed with status: \(process.terminationStatus)")
            try? FileManager.default.removeItem(at: tempFile)
            throw UpdateError.downloadFailed
        }
        
        // Read downloaded file
        let data = try Data(contentsOf: tempFile)
        try? FileManager.default.removeItem(at: tempFile)
        
        let sizeKB = data.count / 1024
        print("✅ Downloaded \(sizeKB) KB")
        
        return data
    }
    
    private func isNewerVersion(latest: String, current: String) -> Bool {
        // Remove 'v' prefix if present
        let latestClean = latest.hasPrefix("v") ? String(latest.dropFirst()) : latest
        let currentClean = current.hasPrefix("v") ? String(current.dropFirst()) : current
        
        // Split into components
        let latestParts = latestClean.split(separator: ".").compactMap { Int($0) }
        let currentParts = currentClean.split(separator: ".").compactMap { Int($0) }
        
        // Compare major.minor.patch
        for i in 0..<min(latestParts.count, currentParts.count) {
            if latestParts[i] > currentParts[i] {
                return true
            } else if latestParts[i] < currentParts[i] {
                return false
            }
        }
        
        // If equal up to this point, newer if latest has more components
        return latestParts.count > currentParts.count
    }
}

enum UpdateError: LocalizedError {
    case invalidURL
    case networkError
    case invalidResponse
    case downloadFailed
    case installFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid update URL"
        case .networkError:
            return "Network error during update check"
        case .invalidResponse:
            return "Invalid response from update server"
        case .downloadFailed:
            return "Failed to download update"
        case .installFailed(let reason):
            return "Installation failed: \(reason)"
        }
    }
}
