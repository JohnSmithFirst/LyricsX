//
//  SystemMediaProxy.swift
//  LyricsX
//
//  macOS 26 上 MediaRemote 私有框架对第三方进程完全封锁，
//  MRMediaRemoteGetNowPlayingInfo 永远返回 NULL。
//  本类通过 Accessibility API 读取播放器窗口标题来获取曲目信息。
//

import Foundation
import AppKit
import Combine
import CXShim
import MusicPlayer

class SystemMediaProxy: MusicPlayerProtocol {

    let name: MusicPlayerName? = nil

    @Published var currentTrack: MusicTrack? = nil
    @Published var playbackState: PlaybackState = .stopped

    var playbackTime: TimeInterval {
        get { playbackState.time }
        set {}
    }

    let objectWillChange = ObservableObjectPublisher()

    var currentTrackWillChange: AnyPublisher<MusicTrack?, Never> {
        $currentTrack.eraseToAnyPublisher()
    }
    var playbackStateWillChange: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    func resume() {}
    func pause() {}
    func skipToNextItem() {}
    func skipToPreviousItem() {}
    func updatePlayerState() { pollNowPlaying() }

    // MARK: - Polling

    private var pollingTimer: Timer?
    private var isPolling = false

    func startPolling(interval: TimeInterval = 1.0) {
        guard !isPolling else { return }
        isPolling = true
        pollNowPlaying()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollNowPlaying()
        }
    }

    func stopPolling() {
        isPolling = false
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    deinit { stopPolling() }

    // MARK: - Known player bundle IDs (by window title pattern)
    
    private static let playerBundleIDs: [String] = [
        "com.foobar2000.mac",
        "com.apple.Music",
        "com.spotify.client",
        "com.coppertino.Vox",
        "com.swinsian.Swinsian",
        "com.colliderli.iina",      // IINA
        "org.videolan.vlc",         // VLC
    ]

    private func pollNowPlaying() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            let running = NSWorkspace.shared.runningApplications
            var foundTitle: String? = nil
            var foundBundleID: String? = nil
            
            for bid in Self.playerBundleIDs {
                guard let app = running.first(where: { $0.bundleIdentifier == bid }),
                      !app.isHidden else { continue }
                
                // Try Accessibility API to read window title
                if let title = self.readWindowTitle(pid: app.processIdentifier, bundleID: bid) {
                    foundTitle = title
                    foundBundleID = bid
                    break
                }
            }
            
            guard let title = foundTitle, !title.isEmpty else {
                DispatchQueue.main.async {
                    self.currentTrack = nil
                    self.playbackState = .stopped
                }
                return
            }
            
            // Parse "Artist - Title" or just "Title"
            let parts = title.components(separatedBy: " - ")
            let artist: String?
            let songTitle: String
            if parts.count >= 2 {
                artist = parts[0].trimmingCharacters(in: .whitespaces)
                songTitle = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            } else {
                artist = nil
                songTitle = title.trimmingCharacters(in: .whitespaces)
            }
            
            // Filter out non-music window titles (e.g. "foobar2000" app name only)
            let appNames = ["foobar2000", "IINA", "VLC", "Music", "Spotify"]
            if appNames.contains(songTitle) { return }
            
            let trackID = "\(foundBundleID ?? "unknown")-\(songTitle)-\(artist ?? "")"
            let track = MusicTrack(id: trackID, title: songTitle, album: nil,
                                   artist: artist, duration: nil, fileURL: nil,
                                   artwork: nil, originalTrack: nil)
            
            DispatchQueue.main.async {
                if self.currentTrack?.id != track.id {
                    self.currentTrack = track
                    self.playbackState = .playing(start: Date())
                }
            }
        }
    }
    
    /// 通过 Accessibility API 读取窗口标题
    private func readWindowTitle(pid: pid_t, bundleID: String) -> String? {
        let app = AXUIElementCreateApplication(pid)
        
        // 获取主窗口
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &windowRef)
        guard result == .success, let window = windowRef else {
            // 尝试 focused window
            var focusedRef: CFTypeRef?
            let r2 = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedRef)
            guard r2 == .success, let w2 = focusedRef else { return nil }
            return readTitleFromWindow(w2 as! AXUIElement)
        }
        return readTitleFromWindow(window as! AXUIElement)
    }
    
    private func readTitleFromWindow(_ window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        guard result == .success, let title = titleRef as? String else { return nil }
        return title
    }
}
