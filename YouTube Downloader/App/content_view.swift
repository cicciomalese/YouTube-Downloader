//
//  ContentView.swift
//  YouTubeDownloader
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var downloader = YouTubeDownloader()
    @StateObject private var updater = YtdlpUpdater()
    @StateObject private var dependencyChecker = DependencyChecker()
    @State private var videoURL: String = ""
    @State private var downloadMode: DownloadMode = .video
    @State private var videoQuality: VideoQuality = .best
    @State private var audioFormat: AudioFormat? = nil
    @State private var audioBitrate: AudioBitrate? = nil
    @State private var normalizeAudio: Bool = false
    @State private var showingFolderPicker = false
    @State private var activeFolderURL: URL? = nil

    @AppStorage("lastDownloadPath") private var savedPath: String = ""
    @AppStorage("pathBookmark") private var savedBookmark: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Missing dependencies banner — takes priority over the update
            // banner since nothing else works until these are resolved.
            if !dependencyChecker.isChecking && !dependencyChecker.allDependenciesAvailable {
                missingDependenciesBanner
            }

            // Update notification banner
            if updater.updateAvailable {
                ZStack(alignment: .leading) {
                    // Progress bar as background (when updating)
                    if updater.isUpdating {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(Color.yellow.opacity(0.3))
                                .frame(width: geometry.size.width * updater.updateProgress)
                                .animation(.easeInOut(duration: 0.2), value: updater.updateProgress)
                        }
                    }

                    // Content on top
                    HStack(spacing: 12) {
                        Text(updater.isUpdating ? "Updating yt-dlp..." : "Download engine (yt-dlp) needs to be updated.")
                            .font(.headline)
                            .foregroundColor(.orange)

                        Spacer()

                        if !updater.isUpdating {
                            Button("Update Now") {
                                Task {
                                    await updater.updateYtdlp()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.yellow)
                            .controlSize(.large)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .frame(minHeight: 44)
                .background(Color(red: 0.3, green: 0.25, blue: 0.2))
                .cornerRadius(8)
            }

            // URL Entry
            VStack(alignment: .leading, spacing: 8) {
                Text("Video/Playlist URL:")
                    .font(.headline)
                    .foregroundColor(.primary)
                TextField("https://www.youtube.com/watch?v=...", text: $videoURL)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                    )
                    .disabled(downloader.isDownloading)
            }

            // Download Mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Download Mode:")
                    .font(.headline)
                    .foregroundColor(.primary)
                Picker("", selection: $downloadMode) {
                    Text("Video").tag(DownloadMode.video)
                    Text("Audio Only").tag(DownloadMode.audioOnly)
                }
                .pickerStyle(.segmented)
                .disabled(downloader.isDownloading)
            }

            // Settings Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings:")
                    .font(.headline)
                    .foregroundColor(.primary)

                // Video Quality (only for video mode)
                if downloadMode == .video {
                    Picker("", selection: $videoQuality) {
                        Text("Best Available").tag(VideoQuality.best)
                        Text("2160p (4K)").tag(VideoQuality.p2160)
                        Text("1440p (2K)").tag(VideoQuality.p1440)
                        Text("1080p (Full HD)").tag(VideoQuality.p1080)
                        Text("720p (HD)").tag(VideoQuality.p720)
                        Text("480p").tag(VideoQuality.p480)
                        Text("360p").tag(VideoQuality.p360)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 292)
                    .disabled(downloader.isDownloading)
                }

                // Audio Format & Bitrate (only for audio mode)
                if downloadMode == .audioOnly {
                    HStack(spacing: 12) {
                        Picker("", selection: $audioFormat) {
                            Text("Default Format").tag(nil as AudioFormat?)
                            Text("MP3").tag(AudioFormat.mp3 as AudioFormat?)
                            Text("M4A (AAC)").tag(AudioFormat.m4a as AudioFormat?)
                            Text("WAV").tag(AudioFormat.wav as AudioFormat?)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                        .disabled(downloader.isDownloading)

                        Picker("", selection: $audioBitrate) {
                            Text("Default Bitrate").tag(nil as AudioBitrate?)
                            Text("128 kbps").tag(AudioBitrate.low128 as AudioBitrate?)
                            Text("192 kbps").tag(AudioBitrate.medium192 as AudioBitrate?)
                            Text("256 kbps").tag(AudioBitrate.high256 as AudioBitrate?)
                            Text("320 kbps").tag(AudioBitrate.high320 as AudioBitrate?)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                        .disabled(downloader.isDownloading || audioFormat == .wav || audioFormat == nil)

                        // Normalize audio checkbox
                        Toggle("Normalize volume", isOn: $normalizeAudio)
                            .disabled(downloader.isDownloading)
                    }
                }
            }

            // Path Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Download Path:")
                    .font(.headline)
                    .foregroundColor(.primary)
                HStack(spacing: 12) {
                    Text(displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)

                    Button("Browse") {
                        showingFolderPicker = true
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.large)
                    .disabled(downloader.isDownloading)
                }
            }

            // Download + Cancel Buttons
            HStack(spacing: 12) {
                Button(action: startDownload) {
                    Text("Download")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    downloader.isDownloading ||
                    videoURL.isEmpty ||
                    savedPath.isEmpty ||
                    !dependencyChecker.allDependenciesAvailable
                )

                Button(action: cancelDownload) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(!downloader.isDownloading)
            }

            // Status Bar with Integrated Progress
            if !downloader.statusMessage.isEmpty {
                ZStack(alignment: .leading) {
                    // Progress bar as background
                    if downloader.isDownloading, let progress = downloader.currentProgress {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(downloader.statusColor.opacity(0.3))
                                .frame(width: geometry.size.width * (progress / 100.0))
                                .animation(.easeInOut(duration: 0.2), value: progress)
                        }
                    }

                    // Status text on top (vertically centered)
                    Text(downloader.statusMessage)
                        .font(.callout)
                        .foregroundColor(downloader.statusColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 44)
                .background(downloader.statusColor.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(20)
        .frame(width: 600)
        .navigationTitle("YouTube Downloader v\(Bundle.main.appVersion)")
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result)
        }
        .onAppear {
            restoreSavedBookmark()

            Task {
                // Local binary resolution and the GitHub version lookup are
                // independent — run them concurrently rather than one after
                // the other so total wait is whichever is slower, not both
                // added together.
                async let dependenciesTask: () = dependencyChecker.checkDependencies()
                async let latestVersionTask = updater.fetchLatestVersion()

                await dependenciesTask
                let latestVersion = await latestVersionTask

                updater.applyUpdateCheck(
                    currentVersion: dependencyChecker.ytdlpVersion,
                    latestVersion: latestVersion
                )
            }
        }
        .onDisappear {
            activeFolderURL?.stopAccessingSecurityScopedResource()
        }
    }

    private var missingDependenciesBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Missing required component\(dependencyChecker.missingDependencyNames.count > 1 ? "s" : ""): \(dependencyChecker.missingDependencyNames.joined(separator: ", "))")
                    .font(.headline)
                    .foregroundColor(.red)

                Spacer()

                Button("Check Again") {
                    Task {
                        await dependencyChecker.checkDependencies()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Text("Install with Homebrew, then click Check Again:")
                .font(.callout)
                .foregroundColor(.secondary)

            Text("brew install \(dependencyChecker.missingDependencyNames.map { $0 }.joined(separator: " "))")
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.35, green: 0.15, blue: 0.15))
        .cornerRadius(8)
    }

    private var displayPath: String {
        savedPath.isEmpty ? "No folder selected" : savedPath
    }

    private func restoreSavedBookmark() {
        guard let bookmarkData = savedBookmark else { return }

        do {
            let (url, _) = try FileHelpers.resolveBookmark(bookmarkData)
            if url.startAccessingSecurityScopedResource() {
                activeFolderURL = url
            }
        } catch {
            print("Failed to restore bookmark: \(error)")
        }
    }

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            if let previousURL = activeFolderURL {
                previousURL.stopAccessingSecurityScopedResource()
            }

            guard url.startAccessingSecurityScopedResource() else {
                downloader.updateStatus("Cannot access folder", color: .red)
                return
            }

            do {
                let bookmark = try FileHelpers.createBookmark(for: url)
                savedBookmark = bookmark
                savedPath = url.path
                activeFolderURL = url

                if downloader.statusMessage.starts(with: "Cannot") ||
                   downloader.statusMessage.starts(with: "Failed") ||
                   downloader.statusMessage.starts(with: "Error") {
                    downloader.statusMessage = ""
                }
            } catch {
                url.stopAccessingSecurityScopedResource()
                downloader.updateStatus("Failed to save folder access: \(error.localizedDescription)", color: .red)
            }

        case .failure(let error):
            downloader.updateStatus("Failed to select folder: \(error.localizedDescription)", color: .red)
        }
    }

    private func startDownload() {
        guard let ytdlpPath = dependencyChecker.ytdlpPath else {
            downloader.updateStatus("yt-dlp is not available", color: .red)
            return
        }

        guard let bookmarkData = savedBookmark else {
            downloader.updateStatus("Please select a download folder first", color: .red)
            return
        }

        do {
            let (url, _) = try FileHelpers.resolveBookmark(bookmarkData)

            guard url.startAccessingSecurityScopedResource() else {
                downloader.updateStatus("Cannot access folder", color: .red)
                return
            }

            Task {
                // Fix WAV bitrate issue: WAV is lossless, ignore bitrate
                let effectiveFormat = audioFormat ?? .m4a
                let effectiveBitrate = effectiveFormat.isLossless ? nil : (audioBitrate ?? .high256)

                await downloader.downloadContent(
                    url: videoURL,
                    destinationPath: url.path,
                    mode: downloadMode,
                    videoQuality: videoQuality,
                    audioFormat: effectiveFormat,
                    audioBitrate: effectiveBitrate,
                    normalizeAudio: normalizeAudio,
                    ytdlpPath: ytdlpPath,
                    ffmpegPath: dependencyChecker.ffmpegPath,
                    securityScopedURL: url
                )

                url.stopAccessingSecurityScopedResource()
            }
        } catch {
            downloader.updateStatus("Failed to access folder: \(error.localizedDescription)", color: .red)
        }
    }

    private func cancelDownload() {
        downloader.cancelDownload()
    }
}

#Preview {
    ContentView()
}
