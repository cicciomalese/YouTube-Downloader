//
//  ProgressParser.swift
//  YouTubeDownloader
//

import Foundation

struct ProgressParser {
    
    struct ParsedProgress {
        let percentage: Double?
        let speed: String?
        let statusMessage: String?
    }
    
    static func parse(_ output: String) -> ParsedProgress {
        var percentage: Double? = nil
        var speed: String? = nil
        var statusMessage: String? = nil
        
        for line in output.components(separatedBy: "\n") {
            // Parse download progress
            if line.contains("[download]") && line.contains("%") {
                let components = line.components(separatedBy: " ").filter { !$0.isEmpty }
                for (index, component) in components.enumerated() {
                    if component.hasSuffix("%") {
                        let percentString = component.replacingOccurrences(of: "%", with: "")
                        if let percent = Double(percentString) {
                            percentage = percent
                            
                            // Extract speed if available
                            if index + 4 < components.count, components[index + 2] == "at" {
                                speed = components[index + 3]
                                statusMessage = "Downloading at \(components[index + 3])"
                            } else {
                                statusMessage = "Downloading..."
                            }
                        }
                        break
                    }
                }
            }
            // Parse processing stages
            else if line.contains("[Merger]") {
                statusMessage = "Merging video and audio..."
            }
            else if line.contains("[ExtractAudio]") {
                statusMessage = "Extracting audio..."
            }
            else if line.contains("[EmbedThumbnail]") {
                statusMessage = "Embedding cover art..."
            }
            else if line.contains("[Metadata]") {
                statusMessage = "Adding metadata..."
            }
        }
        
        return ParsedProgress(
            percentage: percentage,
            speed: speed,
            statusMessage: statusMessage
        )
    }
}
