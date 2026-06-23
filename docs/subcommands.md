---
layout: default
title: Command reference
---

# Command reference

All commands print compact JSON by default. Success is `{"ok": true, ...}`; failure is `{"ok": false, "error": "..."}`.

Every vision command takes the image as the first positional argument. It accepts a file path, `-` for a base64 image on stdin, or the `--clipboard` / `--screen` flags.

**Bounding boxes** are pixel coordinates `[x, y, w, h]` with a top-left origin. Each box also includes `norm`, the same rectangle normalized to `[0, 1]`.

---

## `macvision ocr <image>`

Extract text with `VNRecognizeTextRequest`, which is natively multi-language — pass a list and one request reads every script.

```sh
macvision ocr ./screenshot.png             # auto: broad default languages
macvision ocr ./screenshot.png --lang cjk  # Chinese/Japanese/Korean preset
macvision ocr ./screenshot.png --lang zh-Hans,en-US
macvision ocr -                            # base64 image on stdin
macvision ocr ./scan.png --level fast
```

**Options**

| Option | Default | Description |
|---|---|---|
| `--lang` | `all` preset | Languages/presets, repeatable or comma-separated. Presets: `all`(default),`cjk`,`cn`,`latin`,`en`. Custom set via `$MACVISION_LANG_<NAME>=a,b,c`. e.g. `--lang cjk,en-US` |
| `--level` | `accurate` | `accurate` or `fast` |
| `--min-confidence` | `0` | Drop results below this confidence |
| `--top` | all | Keep at most N results |
| `--no-language-correction` | off | Disable Vision language correction |
| `--clipboard` | off | Read the image from the clipboard |
| `--screen` | off | Take a fresh screenshot first |

**Language presets** — `all` = zh-Hans,zh-Hant,en-US,ja-JP,ko-KR,fr,de,es,pt,it,ru (auto-detect, no `--lang` needed). `cjk` = zh+ja+ko. `cn` = zh-Hans,zh-Hant. `latin`/`european` = en+fr+de+es+pt+it. `en` = en-US only. Define your own: `export MACVISION_LANG_SEA=th-TH,vi-VN,id-ID` then `macvision ocr img.png --lang sea`.

> **CJK ordering note:** Vision prioritizes the *first* CJK language in the list. The `all`/`cjk` presets are zh-first, so Chinese + Latin read reliably, but pure **Japanese/Korean** text can be starved — for those, lead with the language: `--lang ja-JP` / `--lang ko-KR`.

**Output fields**

| Field | Type | Meaning |
|---|---|---|
| `ok` | bool | Success or failure |
| `image` | string | Source label |
| `width`, `height` | int | Image dimensions |
| `languages` | [string] | Languages used |
| `count` | int | Number of text results |
| `confidence` | float | Mean top-candidate confidence (0 if no text). With `count`, lets a caller judge whether to retry with a different `--lang` |
| `texts` | [object] | One per recognized line/word |
| `texts[].text` | string | Top candidate string |
| `texts[].confidence` | float | Candidate confidence |
| `texts[].bbox` | [int]×4 | `[x, y, w, h]` pixels, top-left origin |
| `texts[].norm` | [float]×4 | Same box normalized |
| `texts[].candidates` | [string] | Other candidates, when present |

---

## `macvision classify <image>`

Classify a scene/objects with `VNClassifyImageRequest`, or animal species with `VNRecognizeAnimalsRequest`.

```sh
macvision classify ./photo.jpg --top 5
macvision classify ./photo.jpg --animals
```

**Options**

| Option | Default | Description |
|---|---|---|
| `--top` | `10` | Keep top N labels |
| `--min-confidence` | `0` | Drop labels below this confidence |
| `--animals` | off | Recognize animal species instead of scene |

**Output fields**

| Field | Type | Meaning |
|---|---|---|
| `mode` | string | `scene` or `animals` |
| `count` | int | Number of labels |
| `labels` | [object] | `{name, confidence}` per label |

---

## `macvision detect <image>`

Run one or more detectors in a single pass. With no detector flag it runs the broad set: faces, barcodes, text regions, and horizon. A flag like `--faces` **narrows** to only that detector. `--rects` (document/card rectangles) and `--ocr` (recognize the actual text) are **additive** — `--ocr` runs text recognition on top of whatever else runs, so `detect img --ocr` = broad + read the words.

```sh
macvision detect ./photo.jpg                              # broad: faces, barcodes, text regions, horizon
macvision detect ./shot.png --ocr --lang zh-Hans,en-US   # broad + read the text
macvision detect ./card.jpg --rects                       # document/card rectangles (opt-in)
macvision detect ./qr.png --barcodes --symbologies qr,ean13
macvision detect ./photo.jpg --faces --horizon            # only faces + horizon
```

**Options**

| Option | Default | Description |
|---|---|---|
| `--faces` | off (on by default if none set) | Detect faces |
| `--rects` | off | Detect document/card rectangles |
| `--barcodes` | off (on by default if none set) | Detect barcodes / QR |
| `--text-regions` | off (on by default if none set) | Detect text region boxes (no content) |
| `--ocr` | off | Recognize the actual text (additive) |
| `--lang` | `en-US` | OCR languages with `--ocr` (`zh-Hans`/`zh-Hant` for Chinese) |
| `--horizon` | off (on by default if none set) | Detect horizon angle |
| `--symbologies` | Vision default | `qr,ean13,ean8,upce,code128,code39,code93,datamatrix,pdf417,aztec,itf14` |
| `--min-size` | `0.2` | Minimum rectangle size for `--rects` (0–1) |
| `--min-confidence` | `0` | Drop detections below this confidence |

**Output fields**

| Field | Type | Meaning |
|---|---|---|
| `count` | int | Total detections across detectors |
| `detections.faces` | [object] | `{bbox, norm}` |
| `detections.rectangles` | [object] | `{bbox, norm, corners, confidence}` — `corners` is 4 `[x, y]` pixel points |
| `detections.barcodes` | [object] | `{payload, symbology, bbox, norm}` |
| `detections.texts` | [object] | Recognized text (with `--ocr`): `{text, confidence, bbox, norm}` |
| `detections.text_regions` | [object] | `{bbox, norm, character_count?}` |
| `detections.horizon` | object | `{angle}` in radians |
| `detections.*_count` | int | Per-detector counts |

---

## `macvision document <image>`

Find the document outline (a quadrilateral) with `VNDetectDocumentSegmentationRequest`, so you can crop or deskew it.

```sh
macvision document ./scan.jpg
```

**Output fields**

| Field | Type | Meaning |
|---|---|---|
| `count` | int | Number of documents found |
| `documents` | [object] | `{bbox, norm, corners, confidence}` — `corners` is 4 `[x, y]` pixel points (top-left, top-right, bottom-right, bottom-left) |

---

## `macvision salient <image>`

Produce a saliency heatmap PNG with `VNGenerateAttentionBasedSaliencyImageRequest` (or objectness with `--mode objectness`).

```sh
macvision salient ./photo.jpg
macvision salient ./photo.jpg --mode objectness --output ./heat.png
```

**Output fields**

| Field | Type | Meaning |
|---|---|---|
| `mode` | string | `attention` or `objectness` |
| `mask_width`, `mask_height` | int | Heatmap dimensions |
| `output` | string | Path to the written PNG |
| `saved` | bool | Whether the PNG was written |

---

## `macvision feature <image>`

Image fingerprint via `VNGenerateImageFeaturePrintRequest`. With `--compare`, compute the distance between two images (0 = identical).

```sh
macvision feature ./a.jpg                       # base64 feature vector
macvision feature ./a.jpg --compare ./b.jpg     # distance between two images
macvision feature ./a.jpg --level 2             # higher-precision model (macOS 14+)
```

**Output fields (single)**

| Field | Type | Meaning |
|---|---|---|
| `level` | int | 1 or 2 |
| `element_count` | int | Vector dimensionality |
| `element_type` | string | `float` or `double` |
| `bytes` | int | Raw vector size in bytes |
| `data` | string | Base64-encoded vector bytes |

**Output fields (compare)**

| Field | Type | Meaning |
|---|---|---|
| `compare` | string | Second image label |
| `distance` | float | 0 = identical; larger = more dissimilar |
| `same` | bool | `distance < 0.5` (loose cutoff; pick your own) |

---

## `macvision daemon`

Long-lived daemon that serves NDJSON requests over named pipes (FIFO). Blocks until cancelled.

```sh
macvision daemon --req /tmp/macvision.req --res /tmp/macvision.res &
```

**Options**

| Option | Default | Description |
|---|---|---|
| `--req` | `/tmp/macvision.req` | Request FIFO path |
| `--res` | `/tmp/macvision.res` | Response FIFO path |

**Request schema** — one JSON object per line on the request pipe:

```json
{"action": "ocr", "image": "/tmp/s.png", "lang": ["zh-Hans", "en-US"]}
```

Supported `action` values: `doctor`, `ocr`, `classify`, `detect`, `feature`, `salient`, `document`. Fields mirror the CLI options:

| Action | Fields |
|---|---|
| `ocr` | `image`, `lang`, `level` (`"fast"`), `min_confidence`, `top`, `use_correction` |
| `classify` | `image`, `top`, `min_confidence`, `animals` |
| `detect` | `image`, `faces`, `rects`, `barcodes`, `text_regions`, `horizon`, `symbologies`, `min_size`, `min_confidence` |
| `feature` | `image`, `compare`, `level` (1 or 2) |
| `salient` | `image`, `mode`, `output` |
| `document` | `image` |
| `doctor` | none |

Each request produces one NDJSON response line on the response pipe, identical to the matching CLI command's JSON.

---

## `macvision doctor`

Report the macOS version, architecture, and the supported `Vision` capabilities.

```sh
macvision doctor
```

**Output fields**

| Field | Type | Meaning |
|---|---|---|
| `ok` | bool | Environment is usable (macOS >= 13) |
| `macos_version` | string | e.g. `26.5.1` |
| `architecture` | string | e.g. `arm64` |
| `apple_silicon` | bool | Apple Silicon vs Intel |
| `checks` | [object] | `{name, value, ok, requirement?}` |
| `capabilities` | [object] | `{name, ok, api}` per Vision request |

---

## Common error fields

| Field | Type | Meaning |
|---|---|---|
| `ok` | bool | `false` |
| `error` | string | Human-readable error message |

Common causes:

- **Image not found / not decodable** — check the path, or that stdin base64 is valid.
- **Screen capture failed** — grant Screen Recording to your terminal in System Settings.
- **No image on the clipboard** — copy an image first, then use `--clipboard`.
