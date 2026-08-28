//
//  BundleHelpers.swift
//  YouTubeDownloader
//

import Foundation

struct BundleHelpers {

    // MARK: - Existing accessors (used by YtdlpUpdater's self-update flow,
    // which specifically cares about the bundled copy it manages).

    // Get path to bundled yt-dlp binary
    nonisolated(unsafe) static var ytdlpPath: String {
        if let bundledPath = Bundle.main.path(forResource: "yt-dlp", ofType: nil) {
            return bundledPath
        }
        // Fallback to system installation
        return "/usr/local/bin/yt-dlp"
    }

    // Get path to bundled ffmpeg binary
    nonisolated(unsafe) static var ffmpegPath: String? {
        Bundle.main.path(forResource: "ffmpeg", ofType: nil)
    }

    // Verify binary exists and is executable (file check only — does not run it)
    nonisolated static func verifyBinary(at path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    // MARK: - Verified resolution for pre-download dependency checks
    //
    // GUI-launched apps on macOS inherit a minimal PATH (typically just
    // /usr/bin:/bin:/usr/sbin:/sbin) that excludes Homebrew's
    // /opt/homebrew/bin or /usr/local/bin. Relying on yt-dlp/ffmpeg being
    // found via inherited $PATH silently fails for most users who installed
    // via Homebrew. These resolvers check a bundled copy first, then a fixed
    // list of common install locations, and confirm the binary actually
    // runs rather than just existing on disk.
    //
    // Each resolution captures the version output at the same time it
    // verifies the binary runs, so callers (e.g. the update checker) don't
    // need to spawn a second process just to read the version string.
    //
    // Process completion is awaited via terminationHandler + a checked
    // continuation — never process.waitUntilExit(), which blocks the
    // calling thread — matching the pattern used elsewhere in the app
    // (ProcessManager, AudioNormalizer, YtdlpUpdater).
    //
    // Note: yt-dlp and ffmpeg use different CLI conventions — yt-dlp is
    // GNU-style ("--version"), ffmpeg is single-dash ("-version"). Passing
    // the wrong one causes ffmpeg to reject the argument and exit non-zero,
    // which looks identical to "not installed" unless you inspect stderr.
    // The version flag is therefore configured per binary below.

    struct ResolvedBinary {
        let path: String
        let versionOutput: String?
    }

    private static let ytdlpCandidates = [
        "/opt/homebrew/bin/yt-dlp",   // Apple Silicon Homebrew
        "/usr/local/bin/yt-dlp",      // Intel Homebrew
        "/opt/local/bin/yt-dlp"       // MacPorts
    ]

    private static let ffmpegCandidates = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/local/bin/ffmpeg"
    ]

    /// Resolve a usable yt-dlp binary (path + version), or nil if none found.
    static func resolveYtdlpBinary() async -> ResolvedBinary? {
        let bundled = Bundle.main.path(forResource: "yt-dlp", ofType: nil)
        return await resolve(bundledPath: bundled, candidates: ytdlpCandidates, versionFlag: "--version")
    }

    /// Resolve a usable ffmpeg binary (path + version), or nil if none found.
    static func resolveFfmpegBinary() async -> ResolvedBinary? {
        let bundled = Bundle.main.path(forResource: "ffmpeg", ofType: nil)
        return await resolve(bundledPath: bundled, candidates: ffmpegCandidates, versionFlag: "-version")
    }

    private static func resolve(bundledPath: String?, candidates: [String], versionFlag: String) async -> ResolvedBinary? {
        if let bundledPath, let version = await runVersionCheck(at: bundledPath, versionFlag: versionFlag) {
            return ResolvedBinary(path: bundledPath, versionOutput: version)
        }
        for candidate in candidates {
            if let version = await runVersionCheck(at: candidate, versionFlag: versionFlag) {
                return ResolvedBinary(path: candidate, versionOutput: version)
            }
        }
        return nil
    }

    /// Confirms the binary exists AND actually executes, which catches
    /// broken symlinks, quarantine flags, or architecture mismatches that a
    /// plain file-exists check would miss. Returns the trimmed stdout
    /// output on success (the version string), or nil on any failure.
    /// Non-existent candidates fail immediately at the file check with no
    /// process spawned, so only a genuinely-present binary pays this cost.
    private static func runVersionCheck(at path: String, versionFlag: String) async -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [versionFlag]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
