---
layout: default
title: FAQ
---

# FAQ

## Installation & permissions

### Does OCR need any permission?

No. Reading an image from a file or stdin and running `Vision` on its pixels requires no TCC permission. macvision never calls a permission prompt.

### `--screen` says screencapture failed

`--screen` shells out to the macOS `screencapture` tool, which needs **Screen Recording** granted to your terminal emulator in System Settings > Privacy & Security. Grant it there, then retry.

### `--clipboard` finds no image

Copy an image (not a file reference) to the clipboard first. In Preview or a browser, copy an image, then run `macvision ocr --clipboard`.

### Do I need a terminal emulator app?

For file and stdin input, no. For `--screen` (Screen Recording) and `--clipboard`, macOS TCC grants access to the **terminal emulator app bundle** (Terminal.app, iTerm, Warp), so run macvision from one of those.

---

## OCR

### Which languages are supported?

`VNRecognizeTextRequest` supports 50+ languages. Pass them with `--lang`, e.g. `--lang zh-Hans,en-US`. Common Chinese identifiers are `zh-Hans` (Simplified) and `zh-Hant` (Traditional).

### What does `--level fast` do?

It uses the faster, less accurate recognition path. Useful for huge batches where speed matters more than precision.

### The confidence looks low but the text is right

`VNRecognizedText.confidence` can report modest values even for clean text. The text field is the top candidate; trust it and filter by `min-confidence` only when you need to.

---

## Coordinates

### What origin do bounding boxes use?

Top-left, in pixels: `[x, y, w, h]`. This matches how agents address the screen. `Vision` itself uses normalized bottom-left coordinates; macvision converts for you. The normalized form is in `norm`.

### How do I crop an image to an OCR box?

```sh
BBOX=$(macvision ocr img.png | jq -c '.texts[0].bbox')
# BBOX = [x,y,w,h] in pixels → use sips to crop
```

---

## Detection

### What does `detect` run by default?

If you pass no detector flag, it runs faces, barcodes, text regions, and horizon. Pass `--rects` to add document/card rectangle detection.

### It found no barcodes

Either there is none, or the symbology is not in the default set. Try `--barcodes --symbologies qr,ean13,code128,pdf417,datamatrix`.

---

## feature

### What is a feature-print?

A fixed-length float vector that describes an image's visual content. Identical or near-identical images have a small `distance`. Use it for deduplication and similarity search.

### What threshold means "same image"?

It depends on your data. macvision reports `same` as `distance < 0.5` as a loose hint, but you should calibrate a threshold on your own image set.

---

## Internals

### Why no `NSApplication`?

`Vision`'s `perform(_:)` is synchronous and needs no run loop. macvision only touches AppKit lazily, to read the clipboard. That keeps file/stdin OCR fast and dependency-light.

### Is the binary signed?

Release binaries are ad-hoc signed. Homebrew removes the quarantine attribute in `post_install`. Direct downloads may need:

```sh
xattr -dr com.apple.quarantine /usr/local/bin/macvision
```

### Why FIFO and not HTTP for the daemon?

Named pipes match the shell-native style of the toolchain: `echo ... > req.fifo; cat res.fifo`. There is no port to bind and no HTTP to parse. See [Design]({{ '/design' | relative_url }}).
