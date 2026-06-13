//
//  SystemMediaProxy.swift
//  LyricsX
//
//  macOS 26 上 MediaRemote 完全封锁。通过 proc_pidinfo 获取播放器
//  当前打开的音频文件路径，从路径中解析艺术家和曲目名。
//  格式: ".../Artist - Title.ext"
//

import Foundation
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
    private var lastFilePath: String?

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
                        if self.currentTrack?.id != track.id {
                            self.currentTrack = track
                            self.playbackState = .playing(start: Date())
                            log("SystemMediaProxy: \(artist ?? "?") - \(title) [\(bid)]")
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

    // MARK: - Find audio file via /proc/pid/fd (macOS)

    /// 通过读取进程打开的文件描述符，找到正在播放的音频文件
    private func findAudioFile(pid: pid_t) -> String? {
        // 方法1: 读取 /proc/pid/fd 符号链接（macOS 不支持 procfs）
        // 方法2: 用 libproc proc_pidinfo 获取文件描述符列表
        // 方法3: 用 lsof 命令（最可靠但需要 fork）

        // 使用 proc_pidinfo
        return findAudioFileViaProc(pid: pid)
    }

    private func findAudioFileViaProc(pid: pid_t) -> String? {
        // 先用 lsof 子进程方式（最可靠）
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-p", "\(pid)", "-Fn"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            // lsof -Fn 输出格式: n/path/to/file
            let lines = output.components(separatedBy: "\n")
            for line in lines {
                guard line.hasPrefix("n/") else { continue }
                let path = String(line.dropFirst(1)) // 去掉 'n' 前缀
                let ext = (path as NSString).pathExtension.lowercased()
                if Self.audioExtensions.contains(ext) {
                    return path
                }
            }
        } catch {
            log("SystemMediaProxy: lsof failed: \(error)")
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
