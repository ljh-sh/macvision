import Foundation
import CoreGraphics
import Vision

/// Image-input options shared by every vision subcommand.
let imageInputOpts: [OptMeta] = [
    OptMeta(name: "--clipboard", type: Bool.self, desc: "Read the image from the clipboard"),
    OptMeta(name: "--screen", type: Bool.self, desc: "Take a fresh screenshot first"),
    OptMeta(name: "--orientation", type: String.self, desc: "EXIF orientation: up|down|left|right|... (default: up)"),
]

/// Shorthand language flags shared by `ocr` and `detect --ocr`. Each appends its
/// script(s) to `--lang` at the position it appears on the command line, so
/// `macvision ocr img.png --ja --en` reads Japanese (kanji+kana) first, Latin
/// second — identical to `--lang ja-JP,en-US`. Order matters for CJK: lead with
/// the script you want recognized (Japanese before Chinese, since Vision commits
/// to the first CJK recognizer and won't fall back to kana/Hangul).
let langShortcutOpts: [OptMeta] = [
    OptMeta(name: "--en", type: Bool.self, desc: "Add English (en-US) to --lang", appendsTo: "--lang", appendValue: "en-US"),
    OptMeta(name: "--zh", type: Bool.self, desc: "Add Chinese (zh-Hans,zh-Hant) to --lang", appendsTo: "--lang", appendValue: "zh-Hans,zh-Hant"),
    OptMeta(name: "--ja", type: Bool.self, desc: "Add Japanese (ja-JP) to --lang", appendsTo: "--lang", appendValue: "ja-JP"),
    OptMeta(name: "--ko", type: Bool.self, desc: "Add Korean (ko-KR) to --lang", appendsTo: "--lang", appendValue: "ko-KR"),
]

func parseOrientation(_ s: String?) -> CGImagePropertyOrientation {
    guard let s else { return .up }
    switch s.lowercased() {
    case "up", "1": return .up
    case "down", "3": return .down
    case "left", "8": return .left
    case "right", "6": return .right
    case "upmirrored", "2": return .upMirrored
    case "downmirrored", "4": return .downMirrored
    case "leftmirrored", "5": return .leftMirrored
    case "rightmirrored", "7": return .rightMirrored
    default: return .up
    }
}

/// Resolve + load the image from a parsed command, returning the engine and source.
func loadEngine(_ p: ParsedCmd) throws -> (VisionEngine, ImageSource) {
    let clipboard = p.opt("--clipboard") as Bool? ?? false
    let screen = p.opt("--screen") as Bool? ?? false
    let src = ImageLoader.resolve(arg: p.arg(0), clipboard: clipboard, screen: screen)
    let img = try ImageLoader.load(src)
    let orient = parseOrientation(p.opt("--orientation") as String?)
    return (VisionEngine(image: img, orientation: orient), src)
}

/// Load an engine from a raw source token (used by the FIFO daemon).
func loadEngine(arg: String?) throws -> (VisionEngine, ImageSource) {
    let src = ImageLoader.resolve(arg: arg, clipboard: false, screen: false)
    let img = try ImageLoader.load(src)
    return (VisionEngine(image: img, orientation: .up), src)
}

/// Shared success header for every result.
func baseResult(_ engine: VisionEngine, _ src: ImageSource) -> [String: Any] {
    ["ok": true, "image": ImageLoader.label(src), "width": engine.width, "height": engine.height]
}

// MARK: - Language resolution (OCR)
//
// Vision's VNRecognizeTextRequest is natively multi-language: pass a list and
// one request reads every script in it. So OCR does NOT need maclisten's
// "run N locales, pick best" — instead we resolve a sensible language list
// (broad default, or a named preset, or raw codes).

/// Built-in named language presets for `--lang`.
let builtinLangPresets: [String: [String]] = [
    "all": ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR", "fr-FR", "de-DE", "es-ES", "pt-BR", "it-IT", "ru-RU"],
    "cjk": ["zh-Hans", "zh-Hant", "ja-JP", "ko-KR"],
    "cn": ["zh-Hans", "zh-Hant"],
    "latin": ["en-US", "fr-FR", "de-DE", "es-ES", "pt-BR", "it-IT"],
    "european": ["en-US", "fr-FR", "de-DE", "es-ES", "pt-BR", "it-IT"],
    "en": ["en-US"],
]

/// Resolve a preset name to its language list. A user-defined preset via
/// `$MACVISION_LANG_<NAME>` env overrides/extends the built-in one
/// (e.g. `MACVISION_LANG_SEA=th-TH,vi-VN,id-ID` → `--lang sea`).
func langPreset(_ name: String) -> [String]? {
    let key = name.lowercased()
    if let env = ProcessInfo.processInfo.environment["MACVISION_LANG_\(key.uppercased())"],
       !env.isEmpty {
        return env.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    return builtinLangPresets[key]
}

/// Expand tokens (preset names or raw language codes) into a flat language list.
func expandLangTokens(_ tokens: [String]) -> [String] {
    tokens.flatMap { t -> [String] in
        let trimmed = t.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return [] }
        if let preset = langPreset(trimmed) { return preset }
        return [trimmed]
    }
}

func dedupeStrings(_ xs: [String]) -> [String] {
    var seen = Set<String>(); var out: [String] = []
    for x in xs { if seen.insert(x).inserted { out.append(x) } }
    return out
}

/// Resolve OCR languages: explicit `--lang` > `$MACVISION_LANG` > the `all` preset.
func resolveLangs(_ p: ParsedCmd) -> [String] {
    let raw: [String]? = p.opt("--lang")
    let explicit = expandLangTokens((raw ?? []).flatMap { $0.split(separator: ",").map(String.init) })
    if !explicit.isEmpty { return dedupeStrings(explicit) }
    if let env = ProcessInfo.processInfo.environment["MACVISION_LANG"], !env.isEmpty {
        let list = dedupeStrings(expandLangTokens(env.split(separator: ",").map(String.init)))
        if !list.isEmpty { return list }
    }
    return builtinLangPresets["all"] ?? ["en-US"]
}

/// Resolve OCR languages from a raw token list (daemon requests). Presets expand;
/// empty → the `all` preset.
func resolveLangsList(_ raw: [String]) -> [String] {
    let expanded = dedupeStrings(expandLangTokens(raw))
    return expanded.isEmpty ? (builtinLangPresets["all"] ?? ["en-US"]) : expanded
}
