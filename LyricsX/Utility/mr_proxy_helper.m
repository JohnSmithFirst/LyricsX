//
//  mr_proxy_helper.m
//  LyricsX
//
//  编译为 dylib，由 python3 进程加载。
//  python3 的 bundle ID 是 com.apple.python3，被 mediaremoted 信任。
//  本 dylib 在 python3 进程内运行，因此可以访问 MediaRemote 私有框架。
//

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>

typedef void (*MRGetInfoFunc)(dispatch_queue_t, void(^)(CFDictionaryRef));
typedef void (*MRIsPlayingFunc)(dispatch_queue_t, void(^)(Boolean));

// ============================================================
// 导出：获取正在播放的曲目信息（JSON 字符串）
// 返回的字符串需要调用者 free()
// ============================================================
char* mr_proxy_get_now_playing(void) {
    @autoreleasepool {
        void *h = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        );
        if (!h) {
            return strdup("{\"error\":\"dlopen MediaRemote failed\"}");
        }

        MRGetInfoFunc MRGetInfo = dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
        MRIsPlayingFunc MRIsPlaying = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");

        if (!MRGetInfo || !MRIsPlaying) {
            dlclose(h);
            return strdup("{\"error\":\"dlsym failed\"}");
        }

        dispatch_queue_t q = dispatch_queue_create("com.lyricsx.proxy", DISPATCH_QUEUE_SERIAL);
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        // 先检查是否在播放
        __block BOOL isPlaying = NO;
        __block BOOL gotPlaying = NO;

        MRIsPlaying(q, ^(Boolean playing) {
            isPlaying = (BOOL)playing;
            gotPlaying = YES;
            dispatch_semaphore_signal(sem);
        });
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));

        // 获取曲目信息
        sem = dispatch_semaphore_create(0);
        __block CFDictionaryRef infoRef = NULL;
        __block BOOL gotInfo = NO;

        MRGetInfo(q, ^(CFDictionaryRef info) {
            if (info) CFRetain(info);
            infoRef = info;
            gotInfo = YES;
            dispatch_semaphore_signal(sem);
        });
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"isPlaying"] = @(isPlaying);

        if (infoRef) {
            NSDictionary *d = (__bridge NSDictionary *)infoRef;
            id v;

            if ((v = d[@"kMRMediaRemoteNowPlayingInfoTitle"]))
                result[@"title"] = v;
            if ((v = d[@"kMRMediaRemoteNowPlayingInfoArtist"]))
                result[@"artist"] = v;
            if ((v = d[@"kMRMediaRemoteNowPlayingInfoAlbum"]))
                result[@"album"] = v;
            if ((v = d[@"kMRMediaRemoteNowPlayingInfoDuration"]))
                result[@"duration"] = v;
            if ((v = d[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]))
                result[@"elapsedTime"] = v;
            if ((v = d[@"kMRMediaRemoteNowPlayingInfoUniqueIdentifier"])) {
                result[@"uniqueIdentifier"] = v;
                result[@"id"] = [v description];
            }
            if (!result[@"id"] && result[@"title"]) {
                result[@"id"] = [NSString stringWithFormat:@"NowPlaying-%@-%@-%@",
                    result[@"title"],
                    result[@"album"] ?: @"",
                    result[@"duration"] ?: @0];
            }
            if ((v = d[@"kMRMediaRemoteNowPlayingInfoArtworkData"])) {
                result[@"artworkDataBase64"] = [(NSData *)v base64EncodedStringWithOptions:0];
            }
            CFRelease(infoRef);
        }

        dlclose(h);

        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        if (jsonData) {
            NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            return strdup([jsonStr UTF8String]);
        }
        return strdup("{\"error\":\"JSON serialization failed\"}");
    }
}
