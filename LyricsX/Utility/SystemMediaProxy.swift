//
//  SystemMediaProxy.swift
//  LyricsX
//
//  macOS 15.4+ mediaremoted 只接受 com.apple.* bundle ID。
//  通过 Process 调用 /usr/bin/python3 subprocess 运行 mr_proxy_helper 来访问 MediaRemote。
//  python3 的 bundle ID 是 com.apple.python3，被 mediaremoted 信任。
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

    // MARK: - Helper tool path

    private static var helperPath: String? {
        // CI: packed in Contents/Frameworks/
        if let p = Bundle.main.privateFrameworksURL?
            .appendingPathComponent("mr_proxy_helper").path,
            FileManager.default.fileExists(atPath: p) { return p }
        // Dev: in Carthage build dir
        let dev = "Carthage/Build/Mac/mr_proxy_helper"
        if FileManager.default.fileExists(atPath: dev) { return dev }
        return nil
    }

    private func pollNowPlaying() {
        guard let helperPath = Self.helperPath else {
            log("SystemMediaProxy: mr_proxy_helper not found")
            return
        }

        // python3 进程（com.apple.python3）作为代理运行 helper
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c",
            "import subprocess; r=subprocess.run(['\(helperPath)','get'],capture_output=True,text=True,timeout=5); print(r.stdout.strip())"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty,
                  let jsonData = output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return
            }

            if json["error"] != nil { return }

            let title = json["title"] as? String
            guard let title = title, !title.isEmpty else {
                DispatchQueue.main.async {
                    self.currentTrack = nil
                    self.playbackState = .stopped
                }
                return
            }

            let isPlaying = json["isPlaying"] as? Bool
            let artist = json["artist"] as? String
            let album = json["album"] as? String
            let duration = json["duration"] as? TimeInterval
            let elapsed = json["elapsedTime"] as? TimeInterval
            let trackID = json["id"] as? String ?? "\(title)-\(artist ?? "")-\(album ?? "")"

            let track = MusicTrack(id: trackID, title: title, album: album, artist: artist,
                                   duration: duration, fileURL: nil, artwork: nil, originalTrack: nil)

            let state: PlaybackState
            if isPlaying == true {
                state = .playing(start: Date(timeIntervalSinceNow: -(elapsed ?? 0)))
            } else {
                state = .paused(time: elapsed ?? 0)
            }

            DispatchQueue.main.async {
                let trackChanged = self.currentTrack?.id != track.id
                let stateChanged = self.playbackState != state
                if trackChanged { self.currentTrack = track }
                if stateChanged { self.playbackState = state }
            }
        } catch {
            log("SystemMediaProxy process error: \(error)")
        }
    }
}
