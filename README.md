# macOS YouTube Media Utility

A native macOS app for downloading YouTube video and audio through a graphical interface.

It uses [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) for media retrieval and provides a simpler native workflow around it.

## Download

[**Download the macOS build**](https://github.com/cicciomalese/YouTube-Downloader/releases/download/1.0/YouTube-Downloader-macOS-universal.zip) for both **Apple Silicon and Intel Macs**.

## Important

The downloadable app is ad-hoc signed but not notarized with an Apple Developer ID. macOS may therefore block it after download.

If that happens, move the app to `/Applications` and clear the quarantine attribute once:

```bash
xattr -cr "/Applications/YouTube Downloader.app"
```

## Features

* Native macOS interface
* YouTube video and playlist downloads
* Video quality selection from best available down to 360p
* Audio-only downloads
* MP3, M4A, and WAV output
* Selectable audio bitrates for lossy formats
* Optional audio normalization
* Metadata and thumbnail embedding for standard downloads
* Download progress display
* Download cancellation
* User-selectable local download folder
* `yt-dlp` update checking and updating

## Why I built it

I wanted a simple macOS interface for tasks I would otherwise handle through Terminal with `yt-dlp`.

The app started as a personal utility and evolved through repeated testing, debugging, and refinement.

## Development

The project was developed with AI assistance.

I defined the application requirements and workflow, then used AI to support implementation while testing, debugging, validating, and refining the resulting code.

## Requirements

* macOS
* `yt-dlp`
* `ffmpeg` for media processing, including audio conversion, normalization, metadata handling, and video/audio merging

The current source supports bundled copies of `yt-dlp` and `ffmpeg`, with fallback to certain system installations where applicable.

## Usage

1. Enter a YouTube video or playlist URL.
2. Choose video or audio-only mode.
3. Select the desired quality or audio format.
4. Optionally enable audio normalization.
5. Choose a local download folder.
6. Start the download.
7. Cancel the active download if needed.

The application stores access to the selected download folder using a macOS security-scoped bookmark.

## Responsible use

This project does not host or provide media.

Users are responsible for ensuring that their use of the application complies with applicable copyright law, service terms, and any permissions associated with the media they download.

`yt-dlp` is an independent open-source project and is not maintained as part of this repository.

## Privacy

The public repository does not include downloaded media, local application data, credentials, browser information, logs, or other personal or machine-specific data.
