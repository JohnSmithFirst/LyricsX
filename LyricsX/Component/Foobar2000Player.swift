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
import MusicPlayer
import CXShim

extension MusicPlayers {

    final class Foobar2000: ObservableObject {

        static let cacheFilePath = NSString(string: "~/Library/Caches/foobar2000_nowplaying.txt").expandingTildeInPath

        private var lastTrackID: String?

        @Published var currentTrack: MusicTrack?
        @Published var playbackState: PlaybackState = .stopped

        var name: MusicPlayerName? { nil }

        init() {
            updatePlayerState()
        }

        func updatePlayerState() {
            guard let content = try? String(contentsOfFile: Self.cacheFilePath, encoding: .utf8),
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                // File doesn't exist or is empty — not playing
                if currentTrack != nil {
                    currentTrack = nil
                    playbackState = .stopped
                }
                return
            }

            let parts = content.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
            guard parts.count >= 4 else { return }

            let stateStr = parts[0]
            let title = parts[1]
            let artist = parts[2]
            let album = parts[3]
            let timeStr = parts.count > 4 ? parts[4] : ""

            let trackID = "\(artist)-\(title)-\(album)"
            let duration = parseTotalDuration(timeStr)
            let elapsed = parseElapsedTime(timeStr)

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

            if track.id != lastTrackID {
                lastTrackID = track.id
                currentTrack = track
            }

            switch stateStr.lowercased() {
            case "playing":
                let start = Date().addingTimeInterval(-(elapsed ?? 0))
                playbackState = .playing(start: start)
            case "paused":
                playbackState = .paused(time: elapsed ?? 0)
            default:
                playbackState = .stopped
            }
        }

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

// MARK: - MusicPlayerProtocol

extension MusicPlayers.Foobar2000: MusicPlayerProtocol {

    var currentTrackWillChange: AnyPublisher<MusicTrack?, Never> {
        return $currentTrack.eraseToAnyPublisher()
    }

    var playbackStateWillChange: AnyPublisher<PlaybackState, Never> {
        return $playbackState.eraseToAnyPublisher()
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
}
