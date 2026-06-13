//
//  SelectedPlayer.swift
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
        
        /// macOS 26 上 MediaRemote 被封，用 Accessibility API 读取窗口标题的 fallback
        private var systemMediaProxy: SystemMediaProxy?
        
        var manualUpdateInterval: TimeInterval = 1.0 {
            didSet { scheduleManualUpdate() }
        }
        
        override init() {
            super.init()
            selectPlayer()
            scheduleManualUpdate()
            defaultsObservation = defaults.observe(keys: [.preferredPlayerIndex, .useSystemWideNowPlaying]) { [weak self] in
                self?.selectPlayer()
            }
            manualUpdateObservation = playbackStateWillChange.sink { [weak self] state in
                self?.scheduleManualUpdate()
            }
        }
        
        private func selectPlayer() {
            let idx = defaults[.preferredPlayerIndex]
            if idx == -1 {
                if defaults[.useSystemWideNowPlaying] {
                    if let systemPlayer = MusicPlayers.SystemMedia() {
                        designatedPlayer = systemPlayer
                        systemMediaProxy?.stopPolling()
                        systemMediaProxy = nil
                        
                        // macOS 26: MediaRemote 返回 NULL，1秒后 fallback 到 lsof 文件路径解析
                        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                            guard let self = self,
                                  defaults[.useSystemWideNowPlaying],
                                  self.designatedPlayer === systemPlayer,
                                  systemPlayer.currentTrack == nil else { return }
                            log("SystemMedia no track, fallback to file-path proxy")
                            DispatchQueue.main.async { self.activateAccessibilityProxy() }
                        }
                    } else {
                        activateAccessibilityProxy()
                    }
                } else {
                    systemMediaProxy?.stopPolling()
                    systemMediaProxy = nil
                    let players = MusicPlayerName.scriptableCases.compactMap(MusicPlayers.Scriptable.init)
                    designatedPlayer = MusicPlayers.NowPlaying(players: players)
                }
            } else {
                systemMediaProxy?.stopPolling()
                systemMediaProxy = nil
                designatedPlayer = MusicPlayerName(index: idx).flatMap(MusicPlayers.Scriptable.init)
            }
        }
        
        private func activateAccessibilityProxy() {
            let proxy = SystemMediaProxy()
            systemMediaProxy = proxy
            designatedPlayer = proxy
            proxy.startPolling(interval: manualUpdateInterval)
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
