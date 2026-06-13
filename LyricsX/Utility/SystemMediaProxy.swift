//
//  SystemMediaProxy.swift
//  LyricsX
//
//  通过 lsof 获取音频文件路径，读 foobar2000 metadb.sqlite 获取元数据。
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

    private static let playerBundleIDs = [
        "com.foobar2000.mac",
    ]

    private static let audioExts = Set([
        "flac", "mp3", "ape", "wav", "wv", "m4a", "aac",
        "ogg", "opus", "aiff", "aif", "dsf", "dff", "tak", "mpc"
    ])

    // foobar2000 metadb 路径
    private static let metadbPath = NSHomeDirectory() + "/Library/foobar2000-v2/metadb.sqlite"

    private func pollNowPlaying() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let running = NSWorkspace.shared.runningApplications

            for bid in Self.playerBundleIDs {
                guard let app = running.first(where: { $0.bundleIdentifier == bid }),
                      !app.isHidden else { continue }
                guard let filePath = self.findAudioFile(pid: app.processIdentifier) else { continue }
                guard let (artist, title) = self.readFoobarMetadata(filePath),
                      let title = title, !title.isEmpty else { continue }

                let fileChanged = self.lastFilePath != filePath
                self.lastFilePath = filePath

                let track = MusicTrack(id: "\(bid)-\(artist ?? "")-\(title)",
                    title: title, album: nil, artist: artist,
                    duration: nil, fileURL: URL(fileURLWithPath: filePath),
                    artwork: nil, originalTrack: nil)

                DispatchQueue.main.async {
                    let idChanged = self.currentTrack?.id != track.id
                    if idChanged {
                        self.trackStartTime = Date()
                        self.currentTrack = track
                        self.playbackState = .playing(start: self.trackStartTime!)
                    } else if let start = self.trackStartTime {
                        self.playbackState = .playing(start: start)
                    }
                }
                return
            }
            DispatchQueue.main.async {
                self.currentTrack = nil
                self.playbackState = .stopped
            }
        }
    }

    // MARK: - foobar2000 metadb

    private func readFoobarMetadata(_ audioPath: String) -> (String?, String?) {
        // 用 python3 读 metadb 并解析 info blob
        let script = """
import sqlite3, sys
db = sqlite3.connect('\(Self.metadbPath.replacingOccurrences(of: "'", with: "\\'"))')
rows = db.execute("SELECT info FROM metadb WHERE name LIKE '%' || ? || '%'",
    ['\(audioPath.replacingOccurrences(of: "'", with: "\\'"))'.split('/')[-1].rsplit('.',1)[0]]
).fetchall()
best_artist, best_title = None, None
for (info,) in rows:
    if not info: continue
    parts = info.split(b'\\x00')
    artist, title = None, None
    for i, p in enumerate(parts):
        if i > 0:
            prev = parts[i-1]
            try:
                if prev == b'artist':
                    artist = p.decode('gb2312')
                elif prev == b'title':
                    title = p.decode('gb2312')
            except: pass
    if title: best_title = title
    if artist: best_artist = artist
if best_title:
    print(f"{best_artist or ''}\\n{best_title}")
elif best_artist:
    print(f"{best_artist}\\n")
"""

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = ["-c", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parts = output.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, !parts[1].isEmpty { return (parts[0], parts[1]) }
            if parts.count >= 1, !parts[0].isEmpty { return (parts[0], nil) }
        } catch {}
        return (nil, nil)
    }

    // MARK: - lsof

    private func findAudioFile(pid: pid_t) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "/usr/sbin/lsof -p \(pid) -Fn 2>/dev/null"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            for line in output.components(separatedBy: "\n") {
                guard line.hasPrefix("n/") else { continue }
                let path = String(line.dropFirst())
                let ext = (path as NSString).pathExtension.lowercased()
                if path.hasPrefix("/") && !path.contains("/.com.apple.") && Self.audioExts.contains(ext) {
                    return path
                }
            }
        } catch {}
        return nil
    }
}
