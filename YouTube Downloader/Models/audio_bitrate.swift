//
//  AudioBitrate.swift
//  YouTubeDownloader
//

import Foundation

enum AudioBitrate: String {
    case low128 = "128"
    case medium192 = "192"
    case high256 = "256"
    case high320 = "320"
    
    var kbps: String {
        "\(rawValue)k"
    }
    
    var label: String {
        "\(rawValue) kbps"
    }
}
