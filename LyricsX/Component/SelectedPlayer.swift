//
//  AppController.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import MusicPlayer
import GenericID
import CXShim

extension MusicPlayers {
    
    final class Selected: Agent {
        
        static let shared = MusicPlayers.Selected()
        
        private var defaultsObservation: DefaultsObservation?
        
        private var manualUpdateObservation: AnyCancellable?
        
        var manualUpdateInterval: TimeInterval = 1.0 {
            didSet {
                scheduleManualUpdate()
            }
        }
        
        override init() {
            super.init()
            selectPlayer()
            scheduleManualUpdate()
            defaultsObservation = defaults.observe(keys: [.preferredPlayerIndex, .useSystemWideNowPlaying]) { [weak self] in
                self?.selectPlayer()
            }
            manualUpdateObservation = playbackStateWillChange.sink { [weak self] state in
                if state.isPlaying {
                    self?.scheduleManualUpdate()
                } else {
                    self?.scheduleCanceller?.cancel()
                }
            }
        }
        
        private func selectPlayer() {
            let idx = defaults[.preferredPlayerIndex]
            if idx == -1 {
                if defaults[.useSystemWideNowPlaying] {
                    if let systemPlayer = MusicPlayers.SystemMedia() {
                        designatedPlayer = systemPlayer
                        log("SystemMedia player initialized successfully")
                    } else {
                        // SystemMedia not available on this macOS version
                        // Fall back to auto-detecting Scriptable + Foobar2000 players
                        log("SystemMedia not available (MediaRemote failed to load), falling back to auto-detection")
                        designatedPlayer = createAutoDetectionPlayer()
                    }
                } else {
                    designatedPlayer = createAutoDetectionPlayer()
                }
            } else if idx == 5 {
                // foobar2000 — uses file monitoring via foo-now-playing component
                designatedPlayer = MusicPlayers.Foobar2000()
                log("Selected foobar2000 player (via foo-now-playing)")
            } else {
                designatedPlayer = MusicPlayerName(index: idx).flatMap(MusicPlayers.Scriptable.init)
            }
            log("Player selection: designatedPlayer=\(String(describing: designatedPlayer))")
        }
        
        private func createAutoDetectionPlayer() -> MusicPlayers.NowPlaying {
            var allPlayers: [MusicPlayerProtocol] = MusicPlayerName.scriptableCases.compactMap(MusicPlayers.Scriptable.init)
            // Also add foobar2000 (via foo-now-playing component file monitoring)
            allPlayers.append(MusicPlayers.Foobar2000())
            log("Auto-detecting among \(allPlayers.count) players")
            return MusicPlayers.NowPlaying(players: allPlayers)
        }
        
        private var scheduleCanceller: Cancellable?
        func scheduleManualUpdate() {
            scheduleCanceller?.cancel()
            guard manualUpdateInterval > 0 else { return }
            let q = DispatchQueue.global().cx
            let i: CXWrappers.DispatchQueue.SchedulerTimeType.Stride = .seconds(manualUpdateInterval)
            scheduleCanceller = q.schedule(after: q.now.advanced(by: i), interval: i, tolerance: i * 0.1, options: nil) { [unowned self] in
                self.designatedPlayer?.updatePlayerState()
            }
        }
    }
}
