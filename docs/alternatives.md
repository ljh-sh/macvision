---
layout: default
title: Alternatives
---

# Alternatives

## Tesseract

- **Pros**: cross-platform, many languages, scriptable, open source.
- **Cons**: not Apple Vision — a different and generally less accurate model on macOS; OCR only; needs separate language data.
- **Use when**: you need a portable engine outside the Apple ecosystem, or a language Vision handles poorly.

## macOS Shortcuts (`shortcuts run`)

- **Pros**: built-in, can chain with other actions.
- **Cons**: depends on a hand-built Shortcut; limited, unscriptable output; one Shortcut per task.
- **Use when**: you already have a Shortcut that does exactly what you want.

## Cloud OCR / LLM vision (OpenAI, Google, etc.)

- **Pros**: often more accurate, strong on reasoning about image content.
- **Cons**: requires network and API keys, uploads images to a third party, latency and cost.
- **Use when**: accuracy or reasoning matters more than privacy/latency. macvision can feed these — run `macvision ocr` and send the text to your model.

## `sips` / `screencapture`

- **Pros**: built-in, fast, no dependency.
- **Cons**: image conversion, metadata, and capture only — no vision at all.
- **Use when**: you need to resize/convert an image or take a screenshot, not understand it.

## When to choose macvision

Choose macvision when you want:

- A tiny native binary with no model download and minimal resource use.
- Images processed locally, with no third-party upload.
- Compact JSON output for scripts and agents.
- The full Vision surface — OCR **and** classification, detection, document segmentation, saliency, and feature-prints — behind one interface.
