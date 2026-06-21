---
layout: default
title: Home
---

<div class="hero">
  <h1>macvision</h1>
  <p>Turn any image into agent-friendly JSON — local macOS OCR and image understanding.</p>
  <div class="cta">
    <a class="btn primary" href="{{ '/install' | relative_url }}">Install</a>
    <a class="btn secondary" href="{{ '/subcommands' | relative_url }}">Command reference</a>
    <a class="btn secondary" href="https://github.com/ljh-sh/macvision" target="_blank" rel="noopener">GitHub</a>
  </div>
</div>

## What is macvision?

**macvision** wraps Apple's `Vision` framework in a tiny Swift binary. Point it at a screenshot, photo, or scan and get back text, scene labels, and detected faces, barcodes, and documents — all as compact JSON, all processed on your Mac. There's no big model to download and nothing is uploaded.

Use it wherever you'd otherwise pay for an LLM vision call: OCR the image locally for free, then send only the text to your model.

- *Read a screenshot into text and feed it to an LLM*
- *Find the QR code or the document outline in an image*
- *Get a fingerprint of an image and compare it to another*
- *Know what scene/objects a photo contains*

## At a glance

```sh
macvision ocr ./screenshot.png                       # extract text
macvision ocr ./screenshot.png --lang zh-Hans,en-US   # Chinese + English
macvision classify ./photo.jpg --top 5                # scene/object labels
macvision detect ./photo.jpg --barcodes               # barcodes / QR
macvision feature ./a.jpg --compare ./b.jpg           # image distance
```

Output schema: `{"ok": true, ...}` on success, `{"ok": false, "error": "..."}` on failure.

## For AI agents

Paste this one-line prompt into Claude Code, Cursor, or any agent's system prompt:

```md
Use `macvision` to read images on macOS (OCR, classify, detect). Install if missing: `brew install ljh-sh/cli/macvision`. JSON output, check `ok`. Run `macvision --help` for subcommands.
```

## Where to go next

- [Install macvision]({{ '/install' | relative_url }}) — Homebrew, direct binary, or build from source
- [Command reference]({{ '/subcommands' | relative_url }}) — every subcommand, option, and output field
- [Design & principles]({{ '/design' | relative_url }}) — why macvision is shaped the way it is
- [Why macvision?]({{ '/why' | relative_url }}) — why a CLI over the Vision framework
- [FAQ]({{ '/faq' | relative_url }}) — permissions, screencapture, coordinate conventions
- [Alternatives]({{ '/alternatives' | relative_url }}) — how macvision compares to Tesseract and cloud OCR
