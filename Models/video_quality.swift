//
//  VideoQuality.swift
//  YouTubeDownloader
//

import Foundation

enum VideoQuality {
    case best
    case p2160  // 4K
    case p1440  // 2K
    case p1080  // Full HD
    case p720   // HD
    case p480
    case p360
    
    var label: String {
        switch self {
        case .best: return "best"
        case .p2160: return "2160p"
        case .p1440: return "1440p"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .p360: return "360p"
        }
    }
    
    var formatString: String {
        switch self {
        case .best:
            return "bestvideo[vcodec^=avc1]+bestaudio/best[vcodec^=avc1]/bestvideo+bestaudio/best"
        case .p2160:
            return "bestvideo[height<=2160][vcodec^=avc1]+bestaudio/best[height<=2160][vcodec^=avc1]/bestvideo[height<=2160]+bestaudio/best[height<=2160]"
        case .p1440:
            return "bestvideo[height<=1440][vcodec^=avc1]+bestaudio/best[height<=1440][vcodec^=avc1]/bestvideo[height<=1440]+bestaudio/best[height<=1440]"
        case .p1080:
            return "bestvideo[height<=1080][vcodec^=avc1]+bestaudio/best[height<=1080][vcodec^=avc1]/bestvideo[height<=1080]+bestaudio/best[height<=1080]"
        case .p720:
            return "bestvideo[height<=720][vcodec^=avc1]+bestaudio/best[height<=720][vcodec^=avc1]/bestvideo[height<=720]+bestaudio/best[height<=720]"
        case .p480:
            return "bestvideo[height<=480][vcodec^=avc1]+bestaudio/best[height<=480][vcodec^=avc1]/bestvideo[height<=480]+bestaudio/best[height<=480]"
        case .p360:
            return "bestvideo[height<=360][vcodec^=avc1]+bestaudio/best[height<=360][vcodec^=avc1]/bestvideo[height<=360]+bestaudio/best[height<=360]"
        }
    }
}
