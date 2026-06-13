//
//  SystemMediaProxy.swift
//  LyricsX
//
//  macOS 26 上 MediaRemote 完全封锁。通过 proc_pidinfo 获取播放器
//  当前打开的音频文件路径，从路径中解析艺术家和曲目名。
//  格式: ".../Artist - Title.ext"
//

import Foundation
import AppKit
import Combine
import CXShim
import MusicPlayer
import Darwin

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
    private var lastFilePath: String?
    private var trackStartTime: Date?

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

    // MARK: - Known player bundle IDs

    private static let playerBundleIDs: [String] = [
        "com.foobar2000.mac",
        "com.apple.Music",
        "com.spotify.client",
        "com.coppertino.Vox",
        "com.swinsian.Swinsian",
        "com.colliderli.iina",
        "org.videolan.vlc",
    ]

    private static let audioExtensions = Set([
        "flac", "mp3", "ape", "wav", "wv", "m4a", "aac",
        "ogg", "opus", "aiff", "aif", "dsf", "dff", "tak", "mpc"
    ])

    private func pollNowPlaying() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let running = NSWorkspace.shared.runningApplications

            for bid in Self.playerBundleIDs {
                guard let app = running.first(where: { $0.bundleIdentifier == bid }),
                      !app.isHidden else { continue }

                if let filePath = self.findAudioFile(pid: app.processIdentifier) {
                    let (artist, title) = self.parseFilePath(filePath)

                    guard let title = title, !title.isEmpty else { continue }

                    // 检测文件是否变了（切歌）
                    let fileChanged = self.lastFilePath != filePath
                    self.lastFilePath = filePath

                    let trackID = "\(bid)-\(artist ?? "")-\(title)"
                    let track = MusicTrack(id: trackID, title: title, album: nil,
                                           artist: artist, duration: nil, fileURL: URL(fileURLWithPath: filePath),
                                           artwork: nil, originalTrack: nil)

                    DispatchQueue.main.async {
                        let trackIdChanged = self.currentTrack?.id != track.id
                        
                        // 切歌时重置 startTime，同一首歌保持时间连续性
                        if trackIdChanged {
                            self.trackStartTime = Date()
                            self.currentTrack = track
                            self.playbackState = .playing(start: self.trackStartTime!)
                            log("SystemMediaProxy: \(artist ?? "?") - \(title) [\(bid)]")
                        } else if let start = self.trackStartTime {
                            // 同一首歌：保持 start 不变，让 playbackState.time 自然增长
                            self.playbackState = .playing(start: start)
                        }
                    }
                    return
                }
            }

            // 没有找到播放中的音频文件
            DispatchQueue.main.async {
                self.currentTrack = nil
                self.playbackState = .stopped
            }
        }
    }

    // MARK: - Find audio file via libproc

    /// 通过 libproc proc_pidinfo 获取进程打开的 vnode 文件路径
    private func findAudioFile(pid: pid_t) -> String? {
        // 获取文件描述符列表大小
        let bufSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufSize > 0 else {
            log("SystemMediaProxy: proc_pidinfo size failed: \(bufSize)")
            return nil
        }

        let fdCount = bufSize / Int32(MemoryLayout<proc_fdinfo>.size)
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(fdCount))
        let result = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bufSize)
        guard result > 0 else {
            log("SystemMediaProxy: proc_pidinfo failed")
            return nil
        }

        for i in 0..<Int(result / Int32(MemoryLayout<proc_fdinfo>.size)) {
            guard fds[i].proc_fdtype == PROX_FDTYPE_VNODE else { continue }

            var vnode = vnode_fdinfowithpath()
            let ret = proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDVNODEPATHINFO,
                                     &vnode, Int32(MemoryLayout<vnode_fdinfowithpath>.size))
            guard ret > 0 else { continue }

            let path = withUnsafePointer(to: &vnode.pvip.vip_path) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }

            let ext = (path as NSString).pathExtension.lowercased()
            if path.hasPrefix("/") && !path.contains("/.com.apple.") && Self.audioExtensions.contains(ext) {
                return path
            }
        }
        return nil
    }

    // MARK: - Parse file path

    /// 从文件路径解析艺术家和曲目名
    /// 支持格式:
    ///   "/path/Artist - Title.ext"
    ///   "/path/Artist/Album/Artist - Title.ext"
    ///   "/path/Artist/Album/TrackNum Title.ext"
    private func parseFilePath(_ path: String) -> (artist: String?, title: String?) {
        let filename = (path as NSString).lastPathComponent
        let nameWithoutExt = (filename as NSString).deletingPathExtension

        // 格式1: "Artist - Title"
        if nameWithoutExt.contains(" - ") {
            let parts = nameWithoutExt.components(separatedBy: " - ")
            let artist = parts[0].trimmingCharacters(in: .whitespaces)
            let title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            return (artist: artist, title: title)
        }

        // 格式2: 只有标题，从父目录名推断艺术家
        let parentDir = (path as NSString).deletingLastPathComponent
        let parentName = (parentDir as NSString).lastPathComponent

        // 过滤掉专辑目录名（通常包含年份、括号等）
        let albumPatterns = ["(", "（", "19", "20", "CD", "Disc", "盘"]
        let isAlbumDir = albumPatterns.contains(where: { parentName.contains($0) })
        if isAlbumDir {
            let grandParent = (parentDir as NSString).deletingLastPathComponent
            let grandName = (grandParent as NSString).lastPathComponent
            return (artist: grandName, title: nameWithoutExt)
        }

        return (artist: parentName, title: nameWithoutExt)
    }
}
