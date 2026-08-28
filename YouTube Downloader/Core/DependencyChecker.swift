//
//  DependencyChecker.swift
//  YouTubeDownloader
//
//  Resolves yt-dlp and ffmpeg once (bundled copy, then common install
//  locations) and exposes the result so the UI can block downloads and
//  surface a clear message until both are actually present and runnable.
//
//  Also captures yt-dlp's version string during resolution, so
//  YtdlpUpdater doesn't need to spawn a second `--version` process just
//  to find out what's currently installed.
//

import Foundation
import Combine

@MainActor
class DependencyChecker: ObservableObject {

    @Published var isChecking: Bool = true
    @Published var ytdlpPath: String? = nil
    @Published var ytdlpVersion: String? = nil
    @Published var ffmpegPath: String? = nil

    // Bumped on every call to checkDependencies(). Lets an in-flight call
    // detect that a newer call has since started and discard its own
    // (now-stale) result instead of overwriting a more recent one — e.g.
    // the launch-time check still running when "Check Again" is tapped.
    private var currentGeneration = 0

    var isYtdlpAvailable: Bool { ytdlpPath != nil }
    var isFfmpegAvailable: Bool { ffmpegPath != nil }
    var allDependenciesAvailable: Bool { isYtdlpAvailable && isFfmpegAvailable }

    var missingDependencyNames: [String] {
        var missing: [String] = []
        if !isYtdlpAvailable { missing.append("yt-dlp") }
        if !isFfmpegAvailable { missing.append("ffmpeg") }
        return missing
    }

    /// Resolve both binaries concurrently. Safe to call again later (e.g. a
    /// "Check Again" button) after the user installs something. If a newer
    /// call starts before this one finishes, this call's result is
    /// discarded so a slow, stale call can never overwrite a faster, more
    /// recent — and more accurate — one.
    func checkDependencies() async {
        currentGeneration += 1
        let generation = currentGeneration
        isChecking = true

        async let ytdlpResult = BundleHelpers.resolveYtdlpBinary()
        async let ffmpegResult = BundleHelpers.resolveFfmpegBinary()

        let (ytdlp, ffmpeg) = await (ytdlpResult, ffmpegResult)

        guard generation == currentGeneration else {
            // A newer check superseded this one; don't touch published state.
            return
        }

        ytdlpPath = ytdlp?.path
        ytdlpVersion = ytdlp?.versionOutput
        ffmpegPath = ffmpeg?.path

        isChecking = false
    }
}
