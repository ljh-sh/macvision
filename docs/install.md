---
layout: default
title: Install
---

# Install macvision

## Homebrew (recommended)

```sh
brew install ljh-sh/cli/macvision
```

Or tap once, then use the short name:

```sh
brew tap ljh-sh/cli
brew install macvision
```

## Direct binary

```sh
curl -L https://github.com/ljh-sh/macvision/releases/latest/download/macvision-darwin-universal.tar.xz | tar xJ -
sudo mv bin/macvision /usr/local/bin/
```

The `universal` tarball is a fat Mach-O (arm64 + x86_64) — works on Apple Silicon and Intel Macs.

If macOS blocks the direct download, clear the quarantine attribute:

```sh
xattr -dr com.apple.quarantine /usr/local/bin/macvision
```

## Build from source

Requires Swift 5.10+ / macOS 13+.

```sh
git clone https://github.com/ljh-sh/macvision
cd macvision
swift build -c release
```

The binary will be at `.build/release/macvision`.

## Permissions

OCR, classification, and detection on an image file or stdin need **no** special permission — they use the `Vision` framework directly on pixels you provide.

The optional input sources do need permission:

- **`--screen`** shells out to `screencapture`, which needs **Screen Recording** granted to your terminal in System Settings > Privacy & Security.
- **`--clipboard`** reads the pasteboard, which is generally available to terminal apps.

Run `macvision doctor` to see your environment and the supported capabilities.
