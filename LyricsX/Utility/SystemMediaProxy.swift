//
//  SystemMediaProxy.swift
//  LyricsX
//
//  macOS 15.4+ 的 mediaremoted 只接受 com.apple.* bundle ID 的进程。
//  本类通过 Process 调用 /usr/bin/python3 加载 MRProxyHelper.dylib 来访问 MediaRemote。
//  python3 的 bundle ID 是 com.apple.python3，被 mediaremoted 信任。
//

import Foundation
import Combine
import CXShim
import MusicPlayer

class SystemMediaProxy: MusicPlayerProtocol {

    // MARK: - MusicPlayerProtocol

    let name: MusicPlayerName? = nil

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

    // MARK: - Dylib path

    private static var dylibPath: String? {
        // 查找 MRProxyHelper.dylib（CI 打包进 Contents/Frameworks/）
        if let fwURL = Bundle.main.privateFrameworksURL?
            .appendingPathComponent("MRProxyHelper.dylib")
            .path,
            FileManager.default.fileExists(atPath: fwURL) {
            return fwURL
        }
        if let fwURL2 = Bundle.main.sharedFrameworksURL?
            .appendingPathComponent("MRProxyHelper.dylib")
            .path,
            FileManager.default.fileExists(atPath: fwURL2) {
            return fwURL2
        }
        // 本地开发时，dylib 可能在 build 目录
        let devPaths = [
            "Carthage/Build/Mac/MRProxyHelper.dylib",
            "DerivedData/Build/Products/Release/MRProxyHelper.dylib",
        ]
        for p in devPaths {
            let full = URL(fileURLWithPath: p).path
            if FileManager.default.fileExists(atPath: full) {
                return full
            }
        }
        return nil
    }

    private func pollNowPlaying() {
        guard let dylibPath = Self.dylibPath else {
            log("SystemMediaProxy: MRProxyHelper.dylib not found")
            return
        }

        // python3 脚本：用 ctypes 加载 dylib，调 mr_proxy_get_now_playing()
        let script = """
import ctypes, json, sys
lib = ctypes.cdll.LoadLibrary('\(dylibPath)')
lib.mr_proxy_get_now_playing.argtypes = []
lib.mr_proxy_get_now_playing.restype = ctypes.c_char_p
result_ptr = lib.mr_proxy_get_now_playing()
if result_ptr:
    json_str = ctypes.string_at(result_ptr).decode('utf-8')
    # caller must free the C string
    libc = ctypes.cdll.LoadLibrary(None)
    libc.free(result_ptr)
    print(json_str)
else:
    print(json.dumps({"error":"null result"}))
"""

        let output = runPython3(script: script, dylibPath: dylibPath)

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let error = json["error"] as? String {
            log("SystemMediaProxy error: \(error)")
            return
        }

        let title = json["title"] as? String
        guard let title = title, !title.isEmpty else {
            DispatchQueue.main.async {
                self.currentTrack = nil
                self.playbackState = .stopped
            }
            return
        }

        let isPlaying = json["isPlaying"] as? Bool ?? false
        let artist = json["artist"] as? String
        let album = json["album"] as? String
        let duration = json["duration"] as? TimeInterval
        let elapsed = json["elapsedTime"] as? TimeInterval
        let trackID = json["id"] as? String ?? "\(title)-\(artist ?? "")-\(album ?? "")"

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

        DispatchQueue.main.async {
            let trackChanged = self.currentTrack?.id != track.id
            let stateChanged = self.playbackState != state

            if trackChanged {
                self.currentTrack = track
            }
            if stateChanged {
                self.playbackState = state
            }
        }
    }

    /// 通过 Process 调用 /usr/bin/python3
    private func runPython3(script: String, dylibPath: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script]

        // 通过环境变量确保 python3 能使用正确的路径
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            log("SystemMediaProxy: python3 failed: \(error)")
            return ""
        }
    }
}
