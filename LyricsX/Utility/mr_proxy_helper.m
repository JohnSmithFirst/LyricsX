//
//  mr_proxy_helper - 独立命令行工具
//  由 python3 进程通过 subprocess 调用，python3 的 com.apple.* bundle ID 绕过 mediaremoted 限制。
//  编译: clang -o mr_proxy_helper mr_proxy_helper.m -framework Foundation
//  用法: mr_proxy_helper get     -> JSON 输出当前曲目
//        mr_proxy_helper playing -> 0/1 是否在播放
//

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        const char *cmd = argc > 1 ? argv[1] : "get";

        void *h = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        );
        if (!h) {
            printf("{\"error\":\"dlopen failed\"}\n");
            return 1;
        }

        typedef void (*MRGetInfo_t)(dispatch_queue_t, void(^)(CFDictionaryRef));
        typedef void (*MRIsPlaying_t)(dispatch_queue_t, void(^)(Boolean));

        MRGetInfo_t getInfo = dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
        MRIsPlaying_t isPlayingFn = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");

        if (!getInfo || !isPlayingFn) {
            printf("{\"error\":\"dlsym failed\"}\n");
            dlclose(h);
            return 1;
        }

        dispatch_queue_t q = dispatch_queue_create("mr", DISPATCH_QUEUE_SERIAL);

        if (strcmp(cmd, "playing") == 0) {
            __block BOOL result = NO;
            __block BOOL done = NO;
            isPlayingFn(q, ^(Boolean p) { result = (BOOL)p; done = YES; CFRunLoopStop(CFRunLoopGetMain()); });
            CFAbsoluteTime d = CFAbsoluteTimeGetCurrent() + 3.0;
            while (!done && CFAbsoluteTimeGetCurrent() < d) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
            printf("%d\n", result ? 1 : 0);
        } else {
            __block CFDictionaryRef infoRef = NULL;
            __block BOOL done = NO;
            getInfo(q, ^(CFDictionaryRef info) { if(info) CFRetain(info); infoRef = info; done = YES; CFRunLoopStop(CFRunLoopGetMain()); });
            CFAbsoluteTime d = CFAbsoluteTimeGetCurrent() + 3.0;
            while (!done && CFAbsoluteTimeGetCurrent() < d) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);

            if (infoRef) {
                NSDictionary *dict = (__bridge NSDictionary *)infoRef;
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                id v;
                if ((v = dict[@"kMRMediaRemoteNowPlayingInfoTitle"]))  out[@"title"] = v;
                if ((v = dict[@"kMRMediaRemoteNowPlayingInfoArtist"])) out[@"artist"] = v;
                if ((v = dict[@"kMRMediaRemoteNowPlayingInfoAlbum"]))  out[@"album"] = v;
                if ((v = dict[@"kMRMediaRemoteNowPlayingInfoDuration"])) out[@"duration"] = v;
                if ((v = dict[@"kMRMediaRemoteNowPlayingInfoElapsedTime"])) out[@"elapsedTime"] = v;
                if ((v = dict[@"kMRMediaRemoteNowPlayingInfoUniqueIdentifier"])) { out[@"uniqueIdentifier"] = v; out[@"id"] = [v description]; }
                if (!out[@"id"] && out[@"title"]) out[@"id"] = [NSString stringWithFormat:@"NowPlaying-%@-%@-%@", out[@"title"], out[@"album"]?:@"", out[@"duration"]?:@0];
                NSData *jd = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
                printf("%s\n", [[[NSString alloc] initWithData:jd encoding:NSUTF8StringEncoding] UTF8String]);
                CFRelease(infoRef);
            } else {
                printf("{}\n");
            }
        }
        fflush(stdout);
        dlclose(h);
    }
    return 0;
}
