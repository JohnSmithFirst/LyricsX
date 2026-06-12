//
//  SystemMediaProxy.swift
//  LyricsX
//
//  在 macOS 15.4+ 上，MediaRemote 私有框架的 MRMediaRemoteGetNowPlayingInfo
//  被 mediaremoted 守护进程限制访问。只有 com.apple.* bundle ID 的进程才能获取数据。
//
//  本类通过 AppleScript 轮询已知播放器，获取当前播放曲目信息。
//  实现 MusicPlayerProtocol，可直接作为 designatedPlayer 使用。
//
//  支持的播放器（通过 AppleScript）：
//  - Music (com.apple.Music)
//  - Spotify (com.spotify.client)
//  - Vox (com.coppertino.Vox)
//  - Swinsian (com.swinsian.Swinsian)
//  - Audirvana (com.audirvana.Audirvana*)
//

import Foundation
import AppKit
import Combine
import CXShim
import MusicPlayer

// MARK: - Player Script Info

private struct PlayerScriptInfo {
    let bundleID: String
    let name: String
    let titleScript: String
    let artistScript: String
    let albumScript: String
    let playingScript: String
    let playerPositionScript: String?
    let durationScript: String?
}

private let knownPlayers: [PlayerScriptInfo] = [
    PlayerScriptInfo(
        bundleID: "com.apple.Music",
        name: "Music",
        titleScript: "tell application \"Music\" to if player state is not stopped then name of current track",
        artistScript: "tell application \"Music\" to if player state is not stopped then artist of current track",
        albumScript: "tell application \"Music\" to if player state is not stopped then album of current track",
        playingScript: "tell application \"Music\" to player state is playing",
        playerPositionScript: "tell application \"Music\" to player position",
        durationScript: "tell application \"Music\" to if player state is not stopped then duration of current track"
    ),
    PlayerScriptInfo(
        bundleID: "com.spotify.client",
        name: "Spotify",
        titleScript: "tell application \"Spotify\" to if player state is not stopped then name of current track",
        artistScript: "tell application \"Spotify\" to if player state is not stopped then artist of current track",
        albumScript: "tell application \"Spotify\" to if player state is not stopped then album of current track",
        playingScript: "tell application \"Spotify\" to player state is playing",
        playerPositionScript: "tell application \"Spotify\" to player position",
        durationScript: "tell application \"Spotify\" to if player state is not stopped then duration of current track"
    ),
    PlayerScriptInfo(
        bundleID: "com.coppertino.Vox",
        name: "Vox",
        titleScript: "tell application \"Vox\" to if player state is not stopped then track",
        artistScript: "tell application \"Vox\" to if player state is not stopped then artist",
        albumScript: "tell application \"Vox\" to if player state is not stopped then album",
        playingScript: "tell application \"Vox\" to player state is playing",
        playerPositionScript: "tell application \"Vox\" to player position",
        durationScript: "tell application \"Vox\" to if player state is not stopped then duration"
    ),
    PlayerScriptInfo(
        bundleID: "com.swinsian.Swinsian",
        name: "Swinsian",
        titleScript: "tell application \"Swinsian\" to if player state is not stopped then title of current track",
        artistScript: "tell application \"Swinsian\" to if player state is not stopped then artist of current track",
        albumScript: "tell application \"Swinsian\" to if player state is not stopped then album of current track",
        playingScript: "tell application \"Swinsian\" to playing",
        playerPositionScript: "tell application \"Swinsian\" to elapsed time",
        durationScript: "tell application \"Swinsian\" to if player state is not stopped then duration of current track"
    ),
    PlayerScriptInfo(
        bundleID: "com.audirvana.Audirvana-Studio",
        name: "Audirvana Studio",
        titleScript: "tell application \"Audirvana Studio\" to if playing then title of current track",
        artistScript: "tell application \"Audirvana Studio\" to if playing then artist of current track",
        albumScript: "tell application \"Audirvana Studio\" to if playing then album of current track",
        playingScript: "tell application \"Audirvana Studio\" to playing",
        playerPositionScript: "tell application \"Audirvana Studio\" to player position",
        durationScript: nil
    ),
    PlayerScriptInfo(
        bundleID: "com.audirvana.Audirvana",
        name: "Audirvana",
        titleScript: "tell application \"Audirvana\" to if playing then title of current track",
        artistScript: "tell application \"Audirvana\" to if playing then artist of current track",
        albumScript: "tell application \"Audirvana\" to if playing then album of current track",
        playingScript: "tell application \"Audirvana\" to playing",
        playerPositionScript: "tell application \"Audirvana\" to player position",
        durationScript: nil
    ),
]

// MARK: - SystemMediaProxy

/// 系统级 Now Playing 代理，通过 AppleScript 轮询已知播放器
/// 实现 MusicPlayerProtocol，可直接作为 Agent 的 designatedPlayer
class SystemMediaProxy: MusicPlayerProtocol {
    
    // MARK: - MusicPlayerProtocol
    
    let name: MusicPlayerName? = nil  // 系统级，不绑定特定播放器
    
    @Published var currentTrack: MusicTrack? = nil
    @Published var playbackState: PlaybackState = .stopped
    
    var playbackTime: TimeInterval {
        get { playbackState.time }
        set { /* 不支持设置 */ }
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
    
    func updatePlayerState() {
        // 轮询由内部 timer 驱动，此方法作为手动触发入口
        pollNowPlaying()
    }
    
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
    
    deinit {
        stopPolling()
    }
    
    // MARK: - Polling Logic
    
    private func pollNowPlaying() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            let runningApps = NSWorkspace.shared.runningApplications
            var foundTrack: MusicTrack?
            var foundState: PlaybackState = .stopped
            
            for playerInfo in knownPlayers {
                guard runningApps.contains(where: { $0.bundleIdentifier == playerInfo.bundleID }) else {
                    continue
                }
                
                let result = self.queryPlayer(playerInfo)
                if let track = result.track {
                    foundTrack = track
                    foundState = result.state
                    break
                }
            }
            
            DispatchQueue.main.async {
                let trackChanged = self.currentTrack?.id != foundTrack?.id
                let stateChanged = self.playbackState != foundState
                
                if trackChanged {
                    self.currentTrack = foundTrack
                }
                if stateChanged {
                    self.playbackState = foundState
                }
            }
        }
    }
    
    private struct QueryResult {
        let track: MusicTrack?
        let state: PlaybackState
    }
    
    private func queryPlayer(_ info: PlayerScriptInfo) -> QueryResult {
        let isPlaying = runAppleScript(info.playingScript) == "true"
        
        guard let title = runAppleScript(info.titleScript), !title.isEmpty else {
            return QueryResult(track: nil, state: .stopped)
        }
        
        let artist = runAppleScript(info.artistScript)
        let album = runAppleScript(info.albumScript)
        
        var duration: TimeInterval? = nil
        if let durScript = info.durationScript, let durStr = runAppleScript(durScript) {
            duration = TimeInterval(durStr)
        }
        
        var elapsed: TimeInterval? = nil
        if let posScript = info.playerPositionScript, let posStr = runAppleScript(posScript) {
            elapsed = TimeInterval(posStr)
        }
        
        let trackID = "\(info.bundleID)-\(title)-\(artist ?? "")-\(album ?? "")"
        
        let track = MusicTrack(
            id: trackID,
            title: title,
            album: album,
            artist: artist,
            duration: duration,
            fileURL: nil,
            artwork: nil,
            originalTrack: nil
        )
        
        let state: PlaybackState
        if isPlaying {
            if let elapsed = elapsed {
                state = .playing(start: Date(timeIntervalSinceNow: -elapsed))
            } else {
                state = .playing(start: Date())
            }
        } else {
            if let elapsed = elapsed {
                state = .paused(time: elapsed)
            } else {
                state = .paused(time: 0)
            }
        }
        
        return QueryResult(track: track, state: state)
    }
    
    private func runAppleScript(_ script: String) -> String? {
        guard let appleScript = NSAppleScript(source: script) else {
            return nil
        }
        
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        
        if error != nil {
            return nil
        }
        
        return result.stringValue
    }
}
