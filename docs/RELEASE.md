# Release Guide for LyricsX Fork

## Automated Builds (GitHub Actions)

This fork is configured with GitHub Actions for automated builds and releases.

### How to create a release:

1. **Push a tag** with `v` prefix (e.g., `v1.6.3`):
   ```bash
   git tag v1.6.3
   git push origin v1.6.3
   ```

2. **GitHub Actions** will automatically:
   - Build the app on `macos-latest`
   - Create a ZIP archive of `LyricsX.app`
   - Create a GitHub Release with the build artifact attached

3. **Download** the release from the [Releases page](https://github.com/JohnSmithFirst/LyricsX/releases).

### Manual trigger:
You can also trigger a build manually from the [Actions tab](https://github.com/JohnSmithFirst/LyricsX/actions) using "Run workflow".

## Local Build

```bash
# Install dependencies (if using Carthage)
carthage bootstrap --platform macOS

# Build with Makefile
make build

# Or build with xcodebuild directly
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

## Compatibility

- macOS 10.14+
- Apple Silicon (M1/M2/M3/M4) & Intel
- Requires Accessibility and Automation permissions for music player integration

## Notes

- This is an **unsigned build** for personal use
- For App Store signed builds, use the original project
- First launch: Right-click → Open (to bypass Gatekeeper)
