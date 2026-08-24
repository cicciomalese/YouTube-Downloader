//
//  AudioFormat.swift
//  YouTubeDownloader
//

import Foundation

enum AudioFormat: String {
    case mp3 = "mp3"
    case m4a = "m4a"
    case wav = "wav"
    
    var ffmpegCodec: String {
        switch self {
        case .mp3: return "libmp3lame"
        case .m4a: return "aac"
        case .wav: return "pcm_s16le"
        }
    }
    
    var isLossless: Bool {
        self == .wav
    }
}
