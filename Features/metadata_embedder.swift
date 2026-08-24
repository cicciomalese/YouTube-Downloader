//
//  MetadataEmbedder.swift
//  YouTubeDownloader
//

import Foundation

struct MetadataEmbedder {
    
    // Build yt-dlp arguments for metadata embedding
    static func buildMetadataArguments() -> [String] {
        [
            "--embed-thumbnail",
            "--embed-metadata"
        ]
    }
    
    // Embed metadata using ffmpeg directly (for post-processing)
    static func embedMetadata(
        inputURL: URL,
        outputURL: URL,
        thumbnailURL: URL?,
        ffmpegPath: String
    ) async throws {
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        
        var arguments = ["-i", inputURL.path]
        
        // Add thumbnail if provided
        if let thumbnailURL = thumbnailURL {
            arguments.append(contentsOf: ["-i", thumbnailURL.path])
            arguments.append(contentsOf: [
                "-map", "0:0",
                "-map", "1:0",
                "-c", "copy",
                "-id3v2_version", "3",
                "-metadata:s:v", "title=Album cover",
                "-metadata:s:v", "comment=Cover (front)"
            ])
        } else {
            arguments.append(contentsOf: ["-c", "copy"])
        }
        
        arguments.append(contentsOf: [
            outputURL.path,
            "-y"
        ])
        
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        
        try process.run()
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }
        
        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw DownloaderError.processFailed("Metadata embedding failed: \(errorOutput)")
        }
    }
}
