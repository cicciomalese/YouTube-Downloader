//
//  ProcessManager.swift
//  YouTubeDownloader
//

import Foundation

@MainActor
class ProcessManager {
    
    private var activeProcess: Process?
    
    // Execute yt-dlp with given parameters
    func execute(
        ytdlpPath: String,
        ffmpegPath: String?,
        url: String,
        destinationPath: String,
        mode: DownloadMode,
        videoQuality: VideoQuality,
        audioFormat: AudioFormat,
        audioBitrate: AudioBitrate?,
        progressCallback: @escaping (Double) -> Void,
        statusCallback: @escaping (String) -> Void,
        outputCallback: @escaping (String) -> Void
    ) async throws -> Int32 {
        
        // Create temp directory for intermediate files
        let tempDir = try FileHelpers.createTempDirectory()
        defer {
            FileHelpers.cleanupTempDirectory(tempDir)
        }
        
        // Build arguments
        var arguments = [String]()
        
        // Add ffmpeg location if available
        if let ffmpegPath = ffmpegPath {
            arguments.append("--ffmpeg-location")
            arguments.append(ffmpegPath)
        }
        
        // Use temp directory for intermediate files
        arguments.append("--paths")
        arguments.append("temp:\(tempDir.path)")
        
        // Progress hooks
        arguments.append("--newline")
        arguments.append("--progress")
        
        // Mode-specific arguments
        if mode == .video {
            buildVideoArguments(&arguments, quality: videoQuality, destinationPath: destinationPath)
        } else {
            buildAudioArguments(&arguments, format: audioFormat, bitrate: audioBitrate, destinationPath: destinationPath)
        }
        
        // Metadata embedding
        arguments.append(contentsOf: MetadataEmbedder.buildMetadataArguments())
        
        // Add URL
        arguments.append(url)
        
        print("Running: \(ytdlpPath) \(arguments.joined(separator: " "))")
        
        // Create and configure process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        activeProcess = process
        
        // Actor for thread-safe output collection
        actor OutputCollector {
            var output: String = ""
            func append(_ text: String) {
                output += text
            }
            func get() -> String {
                output
            }
        }
        let collector = OutputCollector()
        
        // Set up output handlers
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            
            Task {
                await collector.append(str)
                print("yt-dlp stdout: \(str)")
                outputCallback(str)
            }
        }
        
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            
            Task {
                await collector.append(str)
                print("yt-dlp stderr: \(str)")
                outputCallback(str)
            }
        }
        
        // Run process
        try process.run()
        
        // Wait for completion
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task.detached {
                process.waitUntilExit()
                
                // Clean up handlers
                await MainActor.run {
                    outputHandle.readabilityHandler = nil
                    errorHandle.readabilityHandler = nil
                }
                
                continuation.resume()
            }
        }
        
        let allOutput = await collector.get()
        
        // Handle termination
        if process.terminationStatus != 0 {
            let errorMsg = allOutput.split(separator: "\n").last.map(String.init) ?? "Unknown error"
            print("yt-dlp FAILED with code \(process.terminationStatus)")
            statusCallback("Download failed: \(errorMsg)")
        }
        
        activeProcess = nil
        return process.terminationStatus
    }
    
    // Cancel active process
    func cancel() {
        activeProcess?.terminate()
        activeProcess = nil
    }
    
    // MARK: - Argument Builders
    
    private func buildVideoArguments(
        _ arguments: inout [String],
        quality: VideoQuality,
        destinationPath: String
    ) {
        arguments.append("-f")
        arguments.append(quality.formatString)
        arguments.append("--merge-output-format")
        arguments.append("mp4")
        
        // Add quality label to filename
        let qualityLabel = " - \(quality.label)"
        arguments.append("-o")
        arguments.append("\(destinationPath)/%(playlist_title|)s/%(title)s\(qualityLabel).%(ext)s")
    }
    
    private func buildAudioArguments(
        _ arguments: inout [String],
        format: AudioFormat,
        bitrate: AudioBitrate?,
        destinationPath: String
    ) {
        arguments.append("-f")
        arguments.append("bestaudio/best")
        arguments.append("-x")
        arguments.append("--audio-format")
        arguments.append(format.rawValue)
        
        // Add bitrate for lossy formats only
        if !format.isLossless, let bitrate = bitrate {
            arguments.append("--audio-quality")
            arguments.append(bitrate.kbps)
        }
        
        // Add bitrate suffix to filename
        let bitrateLabel = format.isLossless ? "lossless" : (bitrate?.rawValue ?? "default") + "k"
        arguments.append("-o")
        arguments.append("\(destinationPath)/%(playlist_title|)s/%(title)s - \(bitrateLabel).%(ext)s")
    }
}
