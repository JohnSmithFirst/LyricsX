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
        
        /// macOS 15.4+ 上 SystemMedia 被 mediaremoted 拒绝时的 fallback
        private var systemMediaProxy: SystemMediaProxy?
        
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
                    // 先尝试 SystemMedia（MediaRemote 私有框架）
                    if let systemPlayer = MusicPlayers.SystemMedia() {
                        // SystemMedia 创建成功，但需要在 macOS 15.4+ 上验证是否真的能获取数据
                        // 先尝试更新一次，如果拿不到 track，则 fallback 到 AppleScript 轮询
                        designatedPlayer = systemPlayer
                        systemMediaProxy?.stopPolling()
                        systemMediaProxy = nil
                        
                        // 延迟检查 SystemMedia 是否能正常工作
                        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
                            guard let self = self,
                                  defaults[.useSystemWideNowPlaying],
                                  self.designatedPlayer === systemPlayer else { return }
                            
                            // 如果 2 秒后仍无 track，说明 SystemMedia 被 mediaremoted 拒绝
                            if systemPlayer.currentTrack == nil {
                                log("SystemMedia returned no track after 2s, falling back to SystemMediaProxy (AppleScript polling)")
                                DispatchQueue.main.async {
                                    self.activateProxyFallback()
                                }
                            }
                        }
                    } else {
                        // SystemMedia 不可用，直接用 AppleScript 轮询
                        activateProxyFallback()
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
        
        /// 激活 AppleScript 轮询代理作为 fallback
        private func activateProxyFallback() {
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
                // 如果使用 SystemMediaProxy，它的 updatePlayerState 会触发 pollNowPlaying
                // 如果使用 SystemMedia，调用 updatePlayerState 通过 MediaRemote 获取
                self.designatedPlayer?.updatePlayerState()
            }
        }
    }
}
