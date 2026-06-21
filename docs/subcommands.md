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

Extract text with `VNRecognizeTextRequest`.

```sh
macvision ocr ./screenshot.png
macvision ocr ./screenshot.png --lang zh-Hans,en-US
macvision ocr -                              # base64 image on stdin
macvision ocr ./scan.png --level fast
```

**Options**

| Option | Default | Description |
|---|---|---|
| `--lang` | `en-US` | Recognition languages, comma-separated. `zh-Hans` / `zh-Hant` for Chinese |
| `--level` | `accurate` | `accurate` or `fast` |
| `--min-confidence` | `0` | Drop results below this confidence |
| `--top` | all | Keep at most N results |
| `--no-language-correction` | off | Disable Vision language correction |
| `--clipboard` | off | Read the image from the clipboard |
| `--screen` | off | Take a fresh screenshot first |

**Output fields**

| Field | Type | Meaning |
|---|---|---|
| `ok` | bool | Success or failure |
| `image` | string | Source label |
| `width`, `height` | int | Image dimensions |
| `languages` | [string] | Languages used |
| `count` | int | Number of text results |
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

Run one or more detectors in a single pass. With no detector flag, it runs faces, barcodes, text regions, and horizon (rectangles are opt-in because they are tuned for cards/documents).

```sh
macvision detect ./photo.jpg
macvision detect ./card.jpg --rects
macvision detect ./qr.png --barcodes --symbologies qr,ean13
macvision detect ./photo.jpg --faces --horizon
```

**Options**

| Option | Default | Description |
|---|---|---|
| `--faces` | off (on by default if none set) | Detect faces |
| `--rects` | off | Detect document/card rectangles |
| `--barcodes` | off (on by default if none set) | Detect barcodes / QR |
| `--text-regions` | off (on by default if none set) | Detect text regions |
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
