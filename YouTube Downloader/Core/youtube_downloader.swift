//
//  YouTubeDownloader.swift
//  YouTubeDownloader
//

import Foundation
import SwiftUI

@MainActor
@Observable
class YouTubeDownloader {
    var isDownloading = false
    var statusMessage = ""
    var statusColor: Color = .secondary
    var currentProgress: Double? = nil

    private let processManager = ProcessManager()

    func cancelDownload() {
        processManager.cancel()
        updateStatus("Download cancelled", color: .orange)
        isDownloading = false
        currentProgress = nil
    }

    func updateStatus(_ message: String, color: Color = .secondary) {
        statusMessage = message
        statusColor = color
        print("Status: \(message)")
    }

    // Main download function.
    // ytdlpPath is required and ffmpegPath is required whenever the mode or
    // settings need it (video merge, audio extraction, normalization) — the
    // caller (ContentView) is expected to have already confirmed both are
    // available via DependencyChecker before enabling the Download button.
    func downloadContent(
        url: String,
        destinationPath: String,
        mode: DownloadMode,
        videoQuality: VideoQuality,
        audioFormat: AudioFormat,
        audioBitrate: AudioBitrate?,
        normalizeAudio: Bool = false,
        ytdlpPath: String,
        ffmpegPath: String?,
        securityScopedURL: URL? = nil
    ) async {
        guard !isDownloading else { return }

        // Validate URL
        guard url.contains("youtube.com") || url.contains("youtu.be") else {
            updateStatus("Invalid YouTube URL", color: .red)
            return
        }

        // Validate writable path
        guard FileHelpers.isWritable(at: destinationPath) else {
            updateStatus("Cannot write to selected folder", color: .red)
            return
        }

        isDownloading = true
        currentProgress = 0
        updateStatus("Starting download...", color: .blue)

        // Route: Normalization vs Standard Download
        if mode == .audioOnly && normalizeAudio {
            guard let ffmpegPath else {
                updateStatus("ffmpeg is required to normalize audio", color: .red)
                isDownloading = false
                currentProgress = nil
                return
            }
            // Route A: Use AudioNormalizer for two-step process
            await downloadWithNormalization(
                url: url,
                destinationPath: destinationPath,
                audioFormat: audioFormat,
                audioBitrate: audioBitrate,
                ytdlpPath: ytdlpPath,
                ffmpegPath: ffmpegPath
            )
        } else {
            // Route B: Use ProcessManager for standard yt-dlp download
            await downloadStandard(
                url: url,
                destinationPath: destinationPath,
                mode: mode,
                videoQuality: videoQuality,
                audioFormat: audioFormat,
                audioBitrate: audioBitrate,
                ytdlpPath: ytdlpPath,
                ffmpegPath: ffmpegPath
            )
        }

        isDownloading = false
        currentProgress = nil
    }

    // Standard download via ProcessManager
    private func downloadStandard(
        url: String,
        destinationPath: String,
        mode: DownloadMode,
        videoQuality: VideoQuality,
        audioFormat: AudioFormat,
        audioBitrate: AudioBitrate?,
        ytdlpPath: String,
        ffmpegPath: String?
    ) async {
        do {
            let terminationStatus = try await processManager.execute(
                ytdlpPath: ytdlpPath,
                ffmpegPath: ffmpegPath,
                url: url,
                destinationPath: destinationPath,
                mode: mode,
                videoQuality: videoQuality,
                audioFormat: audioFormat,
                audioBitrate: audioBitrate,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        self?.currentProgress = progress
                    }
                },
                statusCallback: { [weak self] status in
                    Task { @MainActor in
                        self?.updateStatus(status, color: .blue)
                    }
                },
                outputCallback: { [weak self] output in
                    Task { @MainActor in
                        await self?.handleOutput(output)
                    }
                }
            )

            if terminationStatus == 0 {
                updateStatus("Download completed successfully!", color: .green)
            }

        } catch {
            updateStatus("Error: \(error.localizedDescription)", color: .red)
        }
    }

    // Download with normalization via AudioNormalizer
    private func downloadWithNormalization(
        url: String,
        destinationPath: String,
        audioFormat: AudioFormat,
        audioBitrate: AudioBitrate?,
        ytdlpPath: String,
        ffmpegPath: String
    ) async {
        do {
            // Use yt-dlp to get video title first
            let title = try await fetchVideoTitle(url: url, ytdlpPath: ytdlpPath)

            // Generate output filename with video title
            let sanitizedTitle = sanitizeFilename(title)
            let filename = "\(sanitizedTitle).\(audioFormat.rawValue)"
            let outputURL = URL(fileURLWithPath: destinationPath)
                .appendingPathComponent(filename)

            try await AudioNormalizer.downloadAndNormalize(
                ytdlpPath: ytdlpPath,
                ffmpegPath: ffmpegPath,
                url: url,
                destinationURL: outputURL,
                format: audioFormat,
                bitrate: audioBitrate,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        self?.currentProgress = progress * 100 // Convert to 0-100
                    }
                },
                statusCallback: { [weak self] status in
                    Task { @MainActor in
                        self?.updateStatus(status, color: .blue)
                    }
                }
            )

            updateStatus("Download and normalization completed successfully!", color: .green)

        } catch {
            updateStatus("Error: \(error.localizedDescription)", color: .red)
        }
    }

    // Fetch video title using yt-dlp
    private func fetchVideoTitle(url: String, ytdlpPath: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = ["--get-title", url]

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
        guard let title = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return "audio"
        }

        return title
    }

    // Sanitize filename by removing invalid characters
    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }

    // Handle yt-dlp output
    private func handleOutput(_ output: String) async {
        let parsed = ProgressParser.parse(output)

        if let percentage = parsed.percentage {
            currentProgress = percentage
        }

        if let status = parsed.statusMessage {
            updateStatus(status, color: .blue)
        }
    }
}
