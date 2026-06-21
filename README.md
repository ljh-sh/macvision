# macvision

[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/ljh-sh/macvision/badge)](https://scorecard.dev/)
[![CI](https://github.com/ljh-sh/macvision/actions/workflows/ci.yml/badge.svg)](https://github.com/ljh-sh/macvision/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/Docs-website-blue.svg)](https://ljh-sh.github.io/macvision)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE.txt)

> Turn any image into agent-friendly JSON — local OCR and image understanding on macOS.

**macvision** wraps Apple's `Vision` framework in a tiny Swift binary. Point it at a screenshot, photo, or scan and get back text, scene labels, and detected faces, barcodes, and documents — all as compact JSON, all processed on your Mac. There's no big model to download and nothing is uploaded. Run it wherever you'd otherwise pay for an LLM vision call: OCR the image locally for free, then send only the text to your model.

中文说明见 [README.cn.md](README.cn.md)。

## Highlights

- **No big model to download** — runs on Apple's built-in `Vision` framework; nothing to fetch, cache, or load.
- **Cuts your LLM vision bill** — OCR and detection run free, on-device; send the text to your model instead of paying per image.
- **Protects your privacy — nothing is uploaded** — every image is processed locally on your Mac.
- **Agent-friendly JSON** — compact single-line output and a FIFO daemon, so it drops straight into `jq` pipelines and agent loops.
- **Full Vision surface** — OCR, classification, face/barcode/document detection, document segmentation, saliency heatmaps, and image feature-prints.

Docs: [ljh-sh.github.io/macvision](https://ljh-sh.github.io/macvision)

## For AI agents

Paste this one-line prompt into Claude Code, Cursor, or any agent's system prompt:

```md
Use `macvision` to read images on macOS (OCR, classify, detect). Install if missing: `brew install ljh-sh/cli/macvision`. JSON output, check `ok`. Run `macvision --help` for subcommands.
```

The classic agent loop — *screenshot → read it → reason about it* — becomes one pipe:

```sh
screencapture -i /tmp/s.png
macvision ocr /tmp/s.png --lang zh-Hans,en-US | jq -r '.texts[].text'
```

## Install

### Homebrew (recommended)

```sh
brew install ljh-sh/cli/macvision
```

Or tap once, then use the short name:

```sh
brew tap ljh-sh/cli
brew install macvision
```

### Direct binary

```sh
curl -L https://github.com/ljh-sh/macvision/releases/latest/download/macvision-darwin-universal.tar.xz | tar xJ -
sudo mv bin/macvision /usr/local/bin/
```

The `universal` tarball is a fat Mach-O (arm64 + x86_64) — works on Apple Silicon and Intel Macs.

### Build from source

Requires Swift 5.10+ / macOS 13+.

```sh
git clone https://github.com/ljh-sh/macvision
cd macvision
swift build -c release
```

## Usage

```sh
macvision ocr ./screenshot.png                       # extract text
macvision ocr ./screenshot.png --lang zh-Hans,en-US   # Chinese + English
macvision ocr -                                       # read base64 image from stdin

macvision classify ./photo.jpg --top 5                # scene/object labels
macvision classify ./photo.jpg --animals              # animal species

macvision detect ./photo.jpg                          # faces, barcodes, text regions, horizon
macvision detect ./card.jpg --rects                   # document/card rectangles
macvision detect ./qr.png --barcodes --symbologies qr # barcodes / QR only

macvision document ./scan.jpg                         # document outline (for crop/deskew)
macvision salient ./photo.jpg                         # saliency heatmap PNG
macvision feature ./a.jpg                             # image fingerprint vector
macvision feature ./a.jpg --compare ./b.jpg           # distance between two images
macvision doctor                                      # environment + capability check
```

Image input accepts a file path, `-` for base64 on stdin, or `--clipboard` / `--screen` to read the clipboard or take a fresh screenshot.

Output is JSON by default:

```json
{"ok":true,"image":"./screenshot.png","width":1920,"height":1080,"languages":["zh-Hans","en-US"],"count":3,"texts":[{"text":"你好世界","confidence":0.97,"bbox":[60,495,515,30],"norm":[0.05,0.77,0.43,0.05]}]}
```

Bounding boxes are pixel coordinates `[x, y, w, h]` with the origin at the **top-left** of the image (the convention agents need for screen coordinates). `norm` is the same box normalized to `[0,1]`.

## FIFO daemon

For agents that make many vision calls, `macvision daemon` keeps the framework warm and serves requests over named pipes (no HTTP, no port):

```sh
macvision daemon --req /tmp/macvision.req --res /tmp/macvision.res &
echo '{"action":"ocr","image":"/tmp/s.png","lang":["zh-Hans","en-US"]}' > /tmp/macvision.req
cat /tmp/macvision.res   # one NDJSON response line per request
```

See [docs/subcommands.md](docs/subcommands.md) for the request schema.

## FAQ

See [docs/faq.md](docs/faq.md) or the [published FAQ](https://ljh-sh.github.io/macvision/faq) for permissions, screencapture, coordinate conventions, and how macvision compares to Tesseract and cloud OCR.

## Design

- **Small surface**: `ocr`, `classify`, `detect`, `salient`, `document`, `feature`, `daemon`, `doctor`.
- **JSON output**: compact single-line JSON, easy to pipe to `jq`.
- **No run loop**: `Vision`'s `perform(_:)` is synchronous, so — unlike audio tools — macvision never spins up an `NSApplication` for image work.
- **FIFO IPC**: the daemon speaks NDJSON over named pipes, matching the shell-native style of the surrounding toolchain.

See [CONTRIBUTING.md](CONTRIBUTING.md) and [ROADMAP.md](ROADMAP.md).

## Security

See [SECURITY.md](SECURITY.md).

## License

Apache-2.0
