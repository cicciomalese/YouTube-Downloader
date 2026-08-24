//
//  DownloaderError.swift
//  YouTubeDownloader
//

import Foundation

enum DownloaderError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingBinary(String)
    case processFailed(String)
    case normalizationFailed(String)
    case cannotWriteToPath
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid YouTube URL"
        case .invalidResponse:
            return "Invalid server response"
        case .missingBinary(let name):
            return "\(name) binary not found"
        case .processFailed(let message):
            return "Process failed: \(message)"
        case .normalizationFailed(let message):
            return "Normalization failed: \(message)"
        case .cannotWriteToPath:
            return "Cannot write to selected folder"
        }
    }
}
