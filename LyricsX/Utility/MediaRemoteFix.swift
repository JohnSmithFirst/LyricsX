//
//  MediaRemoteFix.swift
//  LyricsX
//
//  Workaround for Swift 6.1 issue where __attribute__((constructor))
//  in statically-linked ObjC code may not execute before Swift code runs.
//  This ensures MRIsMediaRemoteLoaded is set before SystemMedia.init() checks it.
//

import Foundation
import Darwin

/// Explicitly load MediaRemote symbols to work around Swift 6.1 static linking
/// issue where the MRPrivateLoader constructor might not run in time.
func ensureMediaRemoteLoaded() {
    // MRIsMediaRemoteLoaded is a global bool defined in MRPrivateLoader.m
    // It gets set to true by loadMediaRemote() (constructor).
    // If it's already true, the constructor ran. If not, trigger loading.
    let loaded = dlsym(RLD_DEFAULT, "MRIsMediaRemoteLoaded")?
        .assumingMemoryBound(to: Bool.self)

    if let loaded = loaded {
        if loaded.pointee {
            return // Already loaded by constructor
        }
    }

    // Constructor didn't run or MRIsMediaRemoteLoaded not found.
    // Manually dlopen MediaRemote to trigger symbol resolution.
    // The MRPrivateLoader constructor does:
    //   handle = dlopen("/S/L/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    //   then dlsym each MR function, set MRIsMediaRemoteLoaded = true, dlclose
    guard let handle = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_LAZY
    ) else {
        NSLog("MediaRemoteFix: dlopen MediaRemote failed")
        return
    }

    // Load the required function pointers (same as MRPrivateLoader)
    let symbols: [String] = [
        "MRMediaRemoteSendCommand",
        "MRMediaRemoteSetElapsedTime",
        "MRMediaRemoteGetNowPlayingInfo",
        "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
        "MRMediaRemoteRegisterForNowPlayingNotifications",
        "MRMediaRemoteUnregisterForNowPlayingNotifications",
    ]

    var allLoaded = true
    for sym in symbols {
        let ptr = dlsym(handle, sym)
        if ptr == nil {
            NSLog("MediaRemoteFix: failed to load \(sym)")
            allLoaded = false
        }
        // Store into the global pointers defined by MRPrivateLoader
        // The storage name pattern is: symbol_ (from SLStorage macro)
        let storageName = sym + "_"
        if let storagePtr = dlsym(RLD_DEFAULT, storageName) {
            storagePtr.assumingMemoryBound(to: Optional<UnsafeMutableRawPointer>.self)
                .pointee = ptr
        }
    }

    if allLoaded, let loaded = loaded {
        loaded.pointee = true
        NSLog("MediaRemoteFix: manually loaded all MediaRemote symbols")
    }

    dlclose(handle)
}
