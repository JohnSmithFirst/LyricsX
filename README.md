# LyricsX (M4 Mac Compatible Fork)

[![Build](https://github.com/JohnSmithFirst/LyricsX/actions/workflows/build.yml/badge.svg)](https://github.com/JohnSmithFirst/LyricsX/actions/workflows/build.yml)
[![Telegram](https://img.shields.io/badge/chat-Telegram-blue.svg)](https://telegram.me/LyricsXApp)

<img src="docs/img/icon.png" width="128px">

Ultimate lyrics app for macOS. This fork has been updated for compatibility with modern macOS versions on Apple Silicon (M1/M2/M3/M4) Macs.

Original project: [ddddxxx/LyricsX](https://github.com/ddddxxx/LyricsX)

## Installation

### Download from Releases

Download the latest build from [Releases](https://github.com/JohnSmithFirst/LyricsX/releases).

> **Note:** This is an unsigned build. On first launch, right-click the app and select "Open" to bypass Gatekeeper.

### Homebrew (Original)

```
$ brew install --cask lyricsx
```

### Mac App Store (Original)

[![download on the Mac App Store](docs/img/MAS_badge.svg)](https://itunes.apple.com/us/app/lyricsx/id1254743014?mt=12)

### Requirements

- macOS 10.14+ (Apple Silicon & Intel)
- For Apple Music support on macOS 10.15+, grant Accessibility and Automation permissions

## Features

- Work perfectly with your favorite music players. [List of supported players](https://github.com/ddddxxx/MusicPlayer#supported-players)
- Automatically search & download live lyrics from various lyrics sources.
- Display lyrics on desktop and menubar. you can customize font, color and position.
- Adjust lyrics offset on status menu.
- Navigate the song with lyrics - Double click a line to jump to specific position.
- Drag & Drop to import/export lyrics file.
- Auto launch & quit with music player.
- Automatic conversion between Traditional Chinese and Simplified Chinese.

## Changes in this Fork

- ✅ Updated for macOS 10.14+ (original: 10.11)
- ✅ Added Apple Silicon (arm64) support
- ✅ Fixed deprecated API usage for modern Xcode 16+
- ✅ Updated dependencies (Sparkle 2.x, SnapKit 5.7+, etc.)
- ✅ Replaced `@NSApplicationMain` with `@main`
- ✅ GitHub Actions CI/CD for automated builds and releases
- ✅ Removed legacy Fabric/Crashlytics integration

## Screenshot

<img src="docs/img/desktop_lyrics.gif" width="480px">

<img src="docs/img/preview_1.jpg" width="1280px">

<img src="docs/img/preview_2.jpg" width="1280px">

<img src="docs/img/preview_3.jpg" width="1280px">

## Credit

#### Components

- [LyricsKit](https://github.com/ddddxxx/LyricsKit)
- [MusicPlayer](https://github.com/ddddxxx/MusicPlayer)

#### Open Source Libraries

- [SwiftyOpenCC](https://github.com/ddddxxx/SwiftyOpenCC)
- [GenericID](https://github.com/ddddxxx/GenericID)
- [SwiftCF](https://github.com/ddddxxx/SwiftCF)
- [Regex](https://github.com/ddddxxx/Regex)
- [Semver](https://github.com/ddddxxx/Semver)
- [TouchBarHelper](https://github.com/ddddxxx/TouchBarHelper)
- [CombineX](https://github.com/cx-org/CombineX)
- [SnapKit](https://github.com/SnapKit/SnapKit)
- [MASShortcut](https://github.com/shpakovski/MASShortcut)
- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Then](https://github.com/devxoul/Then)

#### Special Thanks

- [Lyrics Project](https://github.com/MichaelRow/Lyrics)


## ⚠️ Disclaimer

All lyrics are property and copyright of their owners.
