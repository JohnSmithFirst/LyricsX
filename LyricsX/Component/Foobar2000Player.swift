//
//  Foobar2000Player.swift
//  LyricsX
//
//  Monitors the `foo-now-playing` component's output file for foobar2000 track info.
//  The component must be installed: https://github.com/DD00031/foo-now-playing
//  It writes to ~/Library/Caches/foobar2000_nowplaying.txt in format:
//      <status>|<title>|<artist>|<album>|<elapsed/total>
//

import Foundation
import Combine
import MusicPlayer
import CXShim

extension MusicPlayers {

    final class Foobar2000: MusicPlayerProtocol {

        static let cacheFilePath = NSString(string: "~/Library/Caches/foobar2000_nowplaying.txt").expandingTildeInPath

        let objectWillChange = ObservableObjectPublisher()
        let currentTrackWillChange = PassthroughSubject<MusicTrack?, Never>()
        let playbackStateWillChange = PassthroughSubject<PlaybackState, Never>()

        var currentTrack: MusicTrack? {
            didSet { objectWillChange.send() }
        }
        var playbackState: PlaybackState = .stopped {
            didSet { objectWillChange.send() }
        }

        var name: MusicPlayerName? { nil }

        private var lastTrackID: String?

        init() {
            updatePlayerState()
        }

        func updatePlayerState() {
            var newTrack: MusicTrack?
            var newState: PlaybackState = .stopped

            if let content = try? String(contentsOfFile: Self.cacheFilePath, encoding: .utf8),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                let parts = content.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
                if parts.count >= 4 {
                    let stateStr = parts[0]
                    let title = parts[1]
                    let artist = parts[2]
                    let album = parts[3]
                    let timeStr = parts.count > 4 ? parts[4] : ""

                    let trackID = "\(artist)-\(title)-\(album)"
                    let duration = parseTotalDuration(timeStr)
                    let elapsed = parseElapsedTime(timeStr)

                    newTrack = MusicTrack(
                        id: trackID,
                        title: title,
                        album: album,
                        artist: artist,
                        duration: duration,
                        fileURL: nil,
                        artwork: nil,
                        originalTrack: nil
                    )

                    switch stateStr.lowercased() {
                    case "playing":
                        let start = Date().addingTimeInterval(-(elapsed ?? 0))
                        newState = .playing(start: start)
                    case "paused":
                        newState = .paused(time: elapsed ?? 0)
                    default:
                        newState = .stopped
                    }
                }
            }

            // Emit "will change" before updating properties
            if newTrack?.id != currentTrack?.id {
                currentTrackWillChange.send(newTrack)
                currentTrack = newTrack
                lastTrackID = newTrack?.id
            }

            if !playbackState.approximateEqual(to: newState) {
                playbackStateWillChange.send(newState)
                playbackState = newState
            }
        }

        var playbackTime: TimeInterval {
            get { playbackState.time }
            set {
                switch playbackState {
                case .playing:
                    playbackState = .playing(start: Date().addingTimeInterval(-newValue))
                case .paused:
                    playbackState = .paused(time: newValue)
                default:
                    break
                }
            }
        }

        func resume() {}
        func pause() {}
        func skipToNextItem() {}
        func skipToPreviousItem() {}

        private func parseTotalDuration(_ timeStr: String) -> TimeInterval? {
            guard timeStr.contains("/") else { return nil }
            let total = timeStr.components(separatedBy: "/").last ?? ""
            return parseMMSS(total)
        }

        private func parseElapsedTime(_ timeStr: String) -> TimeInterval? {
            guard timeStr.contains("/") else { return parseMMSS(timeStr) }
            let elapsed = timeStr.components(separatedBy: "/").first ?? ""
            return parseMMSS(elapsed)
        }

        private func parseMMSS(_ str: String) -> TimeInterval? {
            let parts = str.components(separatedBy: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else {
                return nil
            }
            return minutes * 60 + seconds
        }
    }
}
