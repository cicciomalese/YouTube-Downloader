//
//  BundleHelpers.swift
//  YouTubeDownloader
//

import Foundation

struct BundleHelpers {
    
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
    
    // Verify binary exists and is executable
    nonisolated static func verifyBinary(at path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
