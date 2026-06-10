# LyricsX — AI 维护上下文手册

> **用途**: 让任何 AI 助手（或新开发者）在新环境下快速理解项目，无需用户重复说明。
> **项目目标**: 将旧的 LyricsX 代码适配到最新 macOS (Apple Silicon M1-M4)，修复编译问题，使其能在 Xcode 16+ 下成功构建。

---

## 1. 项目概览

| 项目 | 说明 |
|------|------|
| **名称** | LyricsX (M4 Mac Compatible Fork) |
| **原始项目** | [ddddxxx/LyricsX](https://github.com/ddddxxx/LyricsX) |
| **Fork 仓库** | [JohnSmithFirst/LyricsX](https://github.com/JohnSmithFirst/LyricsX) |
| **本地路径** | `/Volumes/MyData/workspace/codebuddy/LyricsX` |
| **语言** | Swift 5 |
| **平台** | macOS 10.14+ (arm64 + x86_64) |
| **Xcode** | Xcode 16.4 (CI: `macos-latest`) |
| **许可** | 见 LICENSE 文件 |

---

## 2. 依赖管理（双轨制：SPM + Carthage）

LyricsX 同时使用 **Swift Package Manager** 和 **Carthage** 管理依赖。这在现代 Xcode 项目中比较罕见，是历史遗留问题。

### SPM 依赖（自动解析，19 个包）

| 包名 | 版本 | 来源 | 用途 |
|------|------|------|------|
| CombineX | 0.4.0 | cx-org | Combine 框架的社区替代实现 |
| CXExtensions | 0.4.0 | cx-org | Combine 扩展工具 |
| CXShim | 0.4.0 | cx-org | Combine/CombineX 兼容层 |
| CXTest | 0.4.0 | cx-org | Combine 测试工具 |
| GenericID | 0.7.0 | ddddxxx | UserDefaults 泛型包装 |
| Gzip | 5.1.1 | 1024jp | gzip 压缩解压 |
| LyricsKit | 0.11.0 | ddddxxx | 歌词解析核心库 |
| MusicPlayer | 0.8.2 | ddddxxx | 音乐播放器状态获取 |
| Regex | 1.0.1 | ddddxxx | 正则表达式封装 |
| Semver | 0.2.1 | ddddxxx | 语义版本比较 |
| SwiftCF | 0.2.1 | ddddxxx | Core Foundation 的 Swift 封装 |
| SwiftyOpenCC | v2.0.0-beta | ddddxxx | 简繁中文转换 |
| TouchBarHelper | 0.1.0 | ddddxxx | TouchBar 辅助 |
| AppCenter | 4.1.1 | microsoft | 崩溃报告（可能需要移除） |
| PLCrashReporter | 1.8.1 | microsoft | 崩溃报告（可能需要移除） |
| Sparkle | 1.26.0 | sparkle-project | **旧版** 自动更新框架 |
| swift-atomics | 0.0.3 | apple | 原子操作 |

### Carthage 依赖（需手动构建，3 个包）

| 包名 | 版本 | 来源 | 用途 |
|------|------|------|------|
| SnapKit | 5.7.1 | SnapKit | Auto Layout DSL |
| MASShortcut | 2.4.0 | shpakovski | 全局快捷键绑定 (ObjC) |
| Sparkle | 2.6.4 | sparkle-project | **新版** 自动更新框架 |

> ⚠️ **注意**: Sparkle 同时出现在 SPM (1.26.0) 和 Carthage (2.6.4) 中，存在版本冲突风险。CI 构建中实际使用 Carthage 的 2.6.4 版本。

---

## 3. 项目结构

```
LyricsX/
├── LyricsX.xcodeproj/          # Xcode 项目文件
├── LyricsX/                    # 主应用源代码 (186 文件)
│   ├── Controller/             # 视图控制器
│   │   ├── Preferences/        # 偏好设置面板
│   │   ├── KaraokeLyricsController.swift
│   │   ├── LyricsHUDViewController.swift
│   │   ├── MenuBarLyricsController.swift
│   │   ├── SearchLyricsViewController.swift
│   │   └── TouchBarLyricsController.swift
│   ├── View/                   # 自定义视图
│   │   ├── KaraokeLyricsView.swift
│   │   ├── KaraokeLabel.swift
│   │   ├── ScrollLyricsView.swift
│   │   └── DragNDropView.swift
│   ├── Component/              # 核心组件
│   │   ├── AppDelegate.swift   # ⭐ 应用入口 (含 MASShortcut 快捷键绑定)
│   │   ├── AppController.swift # 主控制器
│   │   ├── Updater.swift       # 自动更新
│   │   └── SelectedPlayer.swift
│   ├── Utility/                # 工具类
│   └── Base.lproj/             # Storyboard 和本地化
├── LyricsXHelper/              # 辅助应用 (AppDelegate.swift)
├── Carthage/                   # Carthage 构建产物 (Build/Mac/)
├── .github/workflows/build.yml # ⭐ CI/CD 自动构建脚本
├── Makefile                    # 本地构建快捷命令
├── Cartfile / Cartfile.resolved
├── docs/                       # 文档和截图
│   └── RELEASE.md
└── .codebuddy/
    └── PROJECT_CONTEXT.md      # ← 本文件
```

---

## 4. 构建方式

### 本地构建

```bash
# 1. 安装 Carthage 依赖（如果本地没有 Carthage/ 目录）
carthage bootstrap --platform macOS

# 2. 构建
make build

# 或直接用 xcodebuild
xcodebuild build \
  -project LyricsX.xcodeproj \
  -scheme LyricsX \
  -configuration Release \
  -derivedDataPath DerivedData \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM=""
```

### CI 构建（GitHub Actions）

触发条件：
- push to master → 自动构建验证
- PR to master → 自动构建验证
- 推送 `v*` 格式的 tag → 构建 + 创建 GitHub Release
- workflow_dispatch → 手动触发

CI 流程：
1. 解析 SPM 依赖 (`xcodebuild -resolvePackageDependencies`)
2. 手动 clone + 编译 Carthage 依赖（SnapKit, MASShortcut）
3. 从 MASShortcut 源码复制头文件 + 使用项目自带的 modulemap（umbrella header 方式）
4. 编译主项目
5. 打包 ZIP 上传为 artifact

---

## 5. 已知问题 & 修复记录

### ✅ 已修复：MASShortcut module.modulemap 编译错误 (2025-06-10)

**症状**: CI 报 `could not build Objective-C module 'MASShortcut'` + `expected module declaration`，随后报 `ERROR: Cannot find Headers directory in MASShortcut.framework`

**根因**: 
1. Xcode 16 的 `xcodebuild build` 动作**不会**将公共头文件复制到 framework bundle 中（只有 `install` 动作才会），所以构建出的 `.framework` 里根本没有 `Headers/` 目录
2. 之前尝试手动生成 modulemap，但语法也有问题（`header` 写在 module 块外部）

**最终修复**: 
- 不再尝试从 framework bundle 中找 Headers，而是直接从 MASShortcut 源码目录 (`/tmp/MASShortcut/Framework/`) 复制 `.h` 文件到 framework 的 `Headers/` 目录
- 不再手动生成 modulemap，而是直接使用 MASShortcut 项目自带的 `MASShortcut.modulemap`（使用 `umbrella header "Shortcut.h"` + `module * { export * }` 方式，更可靠）

### ⚠️ 待处理：Sparkle 版本冲突

SPM 中引用 Sparkle 1.26.0，Carthage 中引用 2.6.4。需要确认实际使用的是哪个版本，避免 API 不兼容。

### ⚠️ 待处理：AppCenter / PLCrashReporter 依赖

这两个是微软的崩溃报告 SDK，可能已被废弃（README 提到 "Removed legacy Fabric/Crashlytics"）。考虑从 Package.resolved 中移除。

---

## 6. 关键技术点

### 为什么 CI 要手动构建 Carthage 依赖？

因为 `carthage bootstrap` 在 CI 环境中非常慢（需要重新编译所有依赖），所以脚本手动 clone 源码并用 `xcodebuild` 只编译需要的 arch (`arm64`)。

### 为什么 MASShortcut 需要手动生成 modulemap？

MASShortcut 是 Objective-C 框架，虽然设置了 `DEFINES_MODULE=YES`，但 Xcode 16 构建出的 framework 可能不自动包含 module.modulemap，或者 Headers 路径不标准。

### 为什么用 `SWIFT_INCLUDE_PATHS`？

CI 脚本通过 `SWIFT_INCLUDE_PATHS="$(pwd)/Carthage/Build/Mac"` 让 Xcode 能找到手动构建的 framework 和 modulemap。

---

## 7. 调试技巧

### 本地模拟 CI 构建

```bash
# 清理 Carthage 缓存
rm -rf Carthage/Build/Mac

# 手动构建 MASShortcut 并检查 modulemap
git clone --depth 1 --branch 2.4.0 https://github.com/shpakovski/MASShortcut.git /tmp/MASShortcut
cd /tmp/MASShortcut
xcodebuild build -project MASShortcut.xcodeproj -scheme MASShortcut -configuration Release \
  -derivedDataPath /tmp/MAS-DD -destination "platform=macOS,arch=arm64" \
  ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  DEFINES_MODULE=YES

# 检查构建产物
find /tmp/MAS-DD -name "MASShortcut.framework" -type d
find /tmp/MAS-DD -path "*/MASShortcut.framework/Headers/*.h"
```

### 检查 module.modulemap 内容

```bash
cat Carthage/Build/Mac/MASShortcut.framework/Modules/module.modulemap
# 期望输出格式:
# framework module MASShortcut {
#   header "MASShortcut.h"
#   header "MASShortcutView.h"
#   ...
#   export *
# }
```

---

## 8. 更新日志

| 日期 | 操作 | 说明 |
|------|------|------|
| 2025-06-10 | 初始上下文创建 | 克隆项目，修复 MASShortcut modulemap CI 错误 |
| - | Fork 创建 | 从原始 ddddxxx/LyricsX fork，更新依赖到现代版本 |

---

## 9. 快速启动检查清单（换电脑后）

1. `git clone git@github.com:JohnSmithFirst/LyricsX.git`
2. `cd LyricsX`
3. 确保 Xcode 16+ 已安装
4. `carthage bootstrap --platform macOS`（或跳过，CI 会处理）
5. 打开 `LyricsX.xcodeproj`，等待 SPM 依赖解析完成
6. 选择 Scheme: `LyricsX`，Destination: `My Mac`
7. Build (Cmd+B)
