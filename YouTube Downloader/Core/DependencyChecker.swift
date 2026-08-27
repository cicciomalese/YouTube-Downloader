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
    /// "Check Again" button) after the user installs something.
    func checkDependencies() async {
        isChecking = true

        async let ytdlpResult = BundleHelpers.resolveYtdlpBinary()
        async let ffmpegResult = BundleHelpers.resolveFfmpegBinary()

        let (ytdlp, ffmpeg) = await (ytdlpResult, ffmpegResult)

        ytdlpPath = ytdlp?.path
        ytdlpVersion = ytdlp?.versionOutput
        ffmpegPath = ffmpeg?.path

        isChecking = false
    }
}
