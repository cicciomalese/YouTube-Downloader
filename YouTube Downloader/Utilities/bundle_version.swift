//
//  Bundle+Version.swift
//  YouTubeDownloader
//
//  Reads the version shown in the footer directly from Info.plist, so it
//  always matches whatever is set in the target's Version/Build fields —
//  nothing to keep in sync by hand.
//

import Foundation

extension Bundle {
    /// User-facing version, e.g. "1.1" — from CFBundleShortVersionString.
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Build number, e.g. "1" — from CFBundleVersion.
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
