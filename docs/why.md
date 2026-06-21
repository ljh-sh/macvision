---
layout: default
title: Why macvision?
---

# Why macvision?

## Privacy by default

macvision sends nothing to a third party:

- Images are processed by Apple's native `Vision` framework.
- No API keys, no image uploads, no cloud billing.
- The `--screen` option uses the local `screencapture` tool; the pixels never leave the Mac.

## Why a CLI over the Vision framework?

Today, getting macOS vision capability into a script or an agent means one of three dead ends:

- **`shortcuts run`** — depends on a hand-built Shortcut, limited output, not scriptable.
- **PyObjC / a Swift script** — every agent re-wraps `Vision`, no shared interface, Python startup cost.
- **`sips`** — image conversion and metadata only; no vision.

macvision is the missing single binary: one JSON interface to the whole `Vision` surface, pipe-friendly, no per-user glue.

## Why not Tesseract?

Tesseract is a capable cross-platform OCR engine, but:

- It is **not** Apple Vision — a different, generally less accurate model on macOS.
- It does OCR only — no scene classification, face/barcode/document detection, saliency, or feature-prints.
- It needs its own language data installed separately.

macvision uses the `Vision` framework that is already installed, optimized, and kept up to date by Apple, and it covers far more than text.

## Why not cloud OCR / LLM vision?

- **No network round-trip** — images stay on the Mac.
- **No API keys, no cost** — uses the system framework.
- **Predictable latency** — no queue, no rate limits.
- **Pipe-friendly** — output JSON drives shell scripts and agents directly.

When you *do* want an LLM to reason about an image, pipe `macvision ocr` (or `classify`) output into it. macvision is the private, local sensing layer; the remote model is the reasoning layer.

## When macvision is the right tool

- You need to read a screenshot, photo, or scan into text.
- You want to detect barcodes, faces, or document outlines in an image.
- You are building an agent that needs vision input on macOS.
- You want to compare or deduplicate images locally with feature-prints.
