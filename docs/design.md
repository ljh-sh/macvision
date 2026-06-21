---
layout: default
title: Design
---

# Design & principles

macvision is intentionally small. It does one thing well: turn images into JSON using Apple's native `Vision` framework.

## Small surface

There are eight top-level commands:

- `ocr` — extract text
- `classify` — scene/object (and animal) labels
- `detect` — faces, rectangles, barcodes, text regions, horizon
- `document` — document outline for crop/deskew
- `salient` — saliency heatmap
- `feature` — image fingerprint and pairwise distance
- `daemon` — long-lived FIFO service
- `doctor` — environment and capability check

No GUI, no model download, no configuration file.

## JSON-first output

Every command prints JSON. This makes macvision easy to pipe into `jq`, Python, or an LLM agent. Errors are also JSON:

```json
{"ok":false,"error":"image load failed: cannot read image at /tmp/missing.png"}
```

## Privacy first

macvision uses the `Vision` framework. It does not bundle a model and does not send images to any third party. Everything happens on the Mac.

## Zero model, zero download

There is no model to fetch, cache, or load into memory. The `Vision` framework ships with macOS and is kept up to date by Apple. The binary is small and starts instantly.

## Coordinates are top-left, in pixels

`Vision` returns geometry in normalized coordinates with a bottom-left origin. macvision converts every box to **pixel** coordinates `[x, y, w, h]` with a **top-left** origin — the convention agents need to map a result back onto the screen. A normalized copy (`norm`, `[0,1]`) is included for resolution-independent use.

## No run loop

`Vision`'s `VNImageRequestHandler.perform(_:)` is synchronous and needs no run loop. So — unlike audio tools — macvision does not start an `NSApplication` for image work. AppKit is touched only lazily, when you read the clipboard.

## FIFO IPC, not HTTP

The `daemon` speaks NDJSON over named pipes (FIFOs), not HTTP. There is no port to bind, no HTTP to parse, and no network stack. This matches the shell-native style of the surrounding toolchain: `echo ... > req.fifo; cat res.fifo`.
