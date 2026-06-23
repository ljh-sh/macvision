# Roadmap

This is the high-level plan for `macvision`. For already-released changes see [`changelog/`](changelog/).

Guiding principle: **macvision only does what is hard to do from shell or Python** — direct use of Apple's `Vision` framework, exposed as JSON-friendly CLI commands and a FIFO daemon.

---

## Shipped

- [x] OCR with language selection and confidence scores (`macvision ocr`)
- [x] Scene and animal classification (`macvision classify`, `--animals`)
- [x] Face / rectangle / barcode / text-region / horizon detection (`macvision detect`)
- [x] Document segmentation for crop/deskew (`macvision document`)
- [x] Saliency heatmaps (`macvision salient`)
- [x] Image feature-prints and pairwise distance (`macvision feature`, `--compare`)
- [x] Image input from file, stdin base64, clipboard, and screenshot
- [x] FIFO daemon with NDJSON IPC (`macvision daemon`)
- [x] Environment and capability check (`macvision doctor`)
- [x] `detect --ocr` — read the actual text inside `detect` (v0.1.1)
- [x] Agent-friendly `--help`: SYNOPSIS / TIP / TLDR (v0.1.1)
- [x] `--version` flag + automatic SLSA provenance on every release (v0.1.2)

---

## v0.2.0 — Hardening & distribution

Goal: harden the detection paths and prepare for broad distribution.

- [ ] Homebrew formula in [`ljh-sh/homebrew-cli`](https://github.com/ljh-sh/homebrew-cli)
- [ ] Signed GitHub releases
- [ ] OpenSSF Scorecard >= 8.5
- [ ] More unit tests for geometry conversion and the CLI parser
- [ ] Determinism / no-leak verification in CI for every release

Success criteria:
- `macvision` installs cleanly via Homebrew.
- CI passes on every PR before merge.

---

## v0.3.0 — Richer vision

Goal: cover more of the `Vision` surface that agents reach for.

- [ ] Face landmarks (`VNDetectFaceLandmarksRequest`)
- [ ] Human body / pose detection
- [ ] Document-camera perspective correction (deskew output)
- [ ] Per-language OCR availability matrix in `doctor`
- [ ] Multi-page PDF input (render each page, OCR in sequence)

---

## Later

- [ ] Video: object / rectangle tracking (`VNTrackObjectRequest`, `VNTrackRectangleRequest`)
- [ ] Camera capture input (`--from-camera`)
- [ ] Optional plain-text / markdown output mode for OCR

---

## Not planned

These are intentionally out of scope for `macvision`:

- **Image editing** (resize, crop, rotate) — use `sips`.
- **OCR engines other than Vision** (Tesseract) — different model, different goals.
- **Cloud OCR / LLM vision** — macvision is the private, local piece; pipe its output to a remote API when you need one.
- **GUI** — macvision is CLI-only by design.
- **Linux / Windows** — macOS-only by design.

---

## How decisions are made

New candidates are evaluated with two questions:

1. Does it map onto a real `Vision` framework request that shell / Python cannot reach reliably?
2. Does centralizing it in `macvision` give agents one stable, JSON-shaped interface instead of N ad-hoc scripts?

If both are yes, it belongs here. If only the second is no, it stays in shell-land.
