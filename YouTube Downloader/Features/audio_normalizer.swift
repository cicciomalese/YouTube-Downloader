//
//  AudioNormalizer.swift
//  YouTubeDownloader
//

import Foundation

class AudioNormalizer {

    // Two-step: download raw audio then normalize.
    // ffmpegPath is expected to be a path already resolved and verified by
    // DependencyChecker — callers should not reach this without one.
    static func downloadAndNormalize(
        ytdlpPath: String,
        ffmpegPath: String,
        url: String,
        destinationURL: URL,
        format: AudioFormat,
        bitrate: AudioBitrate?,
        progressCallback: @escaping (Double) -> Void,
        statusCallback: @escaping (String) -> Void
    ) async throws {

        // Step 1: Download raw audio with yt-dlp (50% of progress)
        // Use proper temp directory and let yt-dlp choose extension
        let tempDir = try FileHelpers.createTempDirectory()
        let tempURL = tempDir.appendingPathComponent("audio.%(ext)s")

        print("📥 Downloading raw audio to temp file...")
        statusCallback("Downloading audio...")
        let startDownload = Date()

        let actualTempFile = try await downloadRawAudio(
            ytdlpPath: ytdlpPath,
            url: url,
            outputTemplate: tempURL.path,
            tempDir: tempDir,
            progressCallback: { downloadProgress in
                progressCallback(downloadProgress * 0.5) // 0-50%
            }
        )

        let downloadTime = Date().timeIntervalSince(startDownload)
        print("✅ Download complete: \(String(format: "%.2f", downloadTime))s")
        print("📁 Temp file: \(actualTempFile.path)")
        progressCallback(0.5)

        // Step 2: Normalize with ffmpeg (50% of progress)
        print("🔧 Starting normalization...")
        let startNormalize = Date()

        try await normalizeAudio(
            ffmpegPath: ffmpegPath,
            inputURL: actualTempFile,
            outputURL: destinationURL,
            format: format,
            bitrate: bitrate,
            statusCallback: statusCallback,
            progressCallback: { normalizeProgress in
                progressCallback(0.5 + (normalizeProgress * 0.5)) // 50-100%
            }
        )

        let normalizeTime = Date().timeIntervalSince(startNormalize)
        print("✅ Normalization complete: \(String(format: "%.2f", normalizeTime))s")

        // Cleanup temp directory
        FileHelpers.cleanupTempDirectory(tempDir)

        progressCallback(1.0)
        print("📊 Total time: \(String(format: "%.2f", Date().timeIntervalSince(startDownload)))s")
    }

    // MARK: - Download Raw Audio

    private static func downloadRawAudio(
        ytdlpPath: String,
        url: String,
        outputTemplate: String,
        tempDir: URL,
        progressCallback: @escaping (Double) -> Void
    ) async throws -> URL {

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)

        // Download ONLY - no audio extraction or conversion
        // Skip metadata embedding since we'll normalize and don't want ReplayGain tags
        process.arguments = [
            "--format", "bestaudio",
            "--output", outputTemplate,
            "--newline",
            "--progress",
            "--no-post-overwrites",
            url
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Parse progress from output
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }

            // Parse yt-dlp progress
            for line in str.components(separatedBy: "\n") {
                if line.contains("[download]") && line.contains("%") {
                    let components = line.components(separatedBy: " ").filter { !$0.isEmpty }
                    for component in components {
                        if component.hasSuffix("%") {
                            let percentString = component.replacingOccurrences(of: "%", with: "")
                            if let percent = Double(percentString) {
                                Task { @MainActor in
                                    progressCallback(percent / 100.0)
                                }
                            }
                            break
                        }
                    }
                }
            }
        }

        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                print("yt-dlp stderr: \(str)")
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        outputHandle.readabilityHandler = nil
        errorHandle.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            throw DownloaderError.processFailed("yt-dlp download failed with code \(process.terminationStatus)")
        }

        // Find the actual downloaded file in temp directory
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        guard let downloadedFile = files.first(where: { $0.lastPathComponent.starts(with: "audio.") }) else {
            throw DownloaderError.processFailed("Downloaded file not found in temp directory")
        }

        if let size = FileHelpers.fileSize(at: downloadedFile) {
            print("💾 Downloaded: \(size)KB")
        }

        return downloadedFile
    }

    // MARK: - Normalize Audio

    private static func normalizeAudio(
        ffmpegPath: String,
        inputURL: URL,
        outputURL: URL,
        format: AudioFormat,
        bitrate: AudioBitrate?,
        statusCallback: @escaping (String) -> Void,
        progressCallback: @escaping (Double) -> Void
    ) async throws {

        statusCallback("Normalizing audio...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)

        // Build arguments array (matching Bandcamp working version)
        var arguments = [
            "-i", inputURL.path,
            "-af", "dynaudnorm=f=500:g=31:p=0.95:m=10:r=0.9:b=1",
            "-ar", "44100"
        ]

        // Add format-specific codec and quality settings
        switch format {
        case .mp3:
            arguments.append(contentsOf: [
                "-codec:a", "libmp3lame",
                "-q:a", "2"
            ])

        case .m4a:
            arguments.append(contentsOf: [
                "-codec:a", "aac",
                "-b:a", bitrate?.kbps ?? "256k"
            ])

        case .wav:
            arguments.append(contentsOf: [
                "-codec:a", "pcm_s16le"
            ])
        }

        arguments.append(contentsOf: [
            outputURL.path,
            "-y"
        ])

        process.arguments = arguments

        print("Running ffmpeg with arguments:")
        print("  Executable: \(ffmpegPath)")
        print("  Arguments: \(arguments)")
        print("  Input exists: \(FileManager.default.fileExists(atPath: inputURL.path))")

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stderrPipe

        // Capture stderr data before process starts
        var errorOutput = ""
        let errorHandle = stderrPipe.fileHandleForReading

        try process.run()

        // Parse ffmpeg progress and capture errors
        Task {
            for try await line in errorHandle.bytes.lines {
                errorOutput += line + "\n"

                if line.contains("time=") {
                    Task { @MainActor in
                        progressCallback(0.5)
                    }
                }
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        guard process.terminationStatus == 0 else {
            print("🔧 ffmpeg failed with status: \(process.terminationStatus)")
            print("🔧 ffmpeg error output:\n\(errorOutput)")
            try? FileManager.default.removeItem(at: outputURL)
            throw DownloaderError.normalizationFailed("ffmpeg exited with code \(process.terminationStatus): \(errorOutput.split(separator: "\n").last ?? "")")
        }

        if let size = FileHelpers.fileSize(at: outputURL) {
            print("💾 Normalized file: \(size)KB")
        }
    }
}
