import Foundation

struct CmdMeta {
    var name: String
    var alias: [String] = []
    var desc: String = ""
    var longDesc: String = ""          // longer DESCRIPTION paragraph
    var tips: [String] = []            // TIP blocks under DESCRIPTION
    var notes: [String] = []           // NOTE blocks under DESCRIPTION
    var synopsis: [String] = []        // SYNOPSIS usage lines
    var tldr: [(String, String)] = []  // TLDR: (short desc, example command)
    var opts: [OptMeta] = []
    var args: [ArgMeta] = []
    var subcmds: [String: Cmd.Type] = [:]
    var run: ((ParsedCmd) async throws -> Void)?
}

struct OptMeta {
    var name: String
    var alias: String?
    var type: Any.Type = String.self
    var desc: String = ""
    var required: Bool = false
    var `default`: Any?
}

struct ArgMeta {
    var name: String
    var desc: String = ""
    var required: Bool = true
}

struct ParsedCmd {
    var opts: [String: Any] = [:]
    var args: [String] = []

    func opt<T>(_ name: String) -> T? {
        opts[name] as? T
    }

    func arg(_ idx: Int) -> String? {
        idx < args.count ? args[idx] : nil
    }
}

protocol Cmd {
    static var meta: CmdMeta { get }
}

func runCmd(_ type: Cmd.Type, _ args: [String]) async throws {
    let meta = type.meta

    if args.first == "--help" || args.first == "-h" {
        printCmdHelp(type)
        return
    }

    var parsed = ParsedCmd()
    var i = 0
    while i < args.count {
        let a = args[i]

        if let subcmdType = meta.subcmds[a] ?? meta.subcmds.values.first(where: { $0.meta.alias.contains(a) }) {
            try await runCmd(subcmdType, Array(args.dropFirst(i + 1)))
            return
        }

        // A lone "-" is the stdin convention, not an option flag.
        if a == "-" {
            parsed.args.append(a)
            i += 1
            continue
        }

        if a.hasPrefix("-") {
            let optName: String
            let explicitValue: String?
            if a.hasPrefix("--"), let eqIdx = a.firstIndex(of: "=") {
                optName = String(a[..<eqIdx])
                explicitValue = String(a[a.index(after: eqIdx)...])
            } else {
                optName = a
                explicitValue = nil
            }
            if let optMeta = meta.opts.first(where: { $0.name == optName || $0.alias == optName }) {
                if optMeta.type is Bool.Type {
                    parsed.opts[optMeta.name] = true
                } else {
                    let raw: String
                    if let v = explicitValue {
                        raw = v
                    } else {
                        i += 1
                        guard i < args.count else { cmdError("missing value for \(optName)") }
                        raw = args[i]
                    }
                    if optMeta.type is Int.Type {
                        guard let v = Int(raw) else { cmdError("\(optName) requires an integer") }
                        parsed.opts[optMeta.name] = v
                    } else if optMeta.type is Double.Type {
                        guard let v = Double(raw) else { cmdError("\(optName) requires a number") }
                        parsed.opts[optMeta.name] = v
                    } else if optMeta.type is [String].Type {
                        parsed.opts[optMeta.name] = raw.split(separator: ",").map(String.init)
                    } else {
                        parsed.opts[optMeta.name] = raw
                    }
                }
            }
        } else {
            parsed.args.append(a)
        }
        i += 1
    }

    if let handler = meta.run {
        try await handler(parsed)
    } else if !meta.subcmds.isEmpty {
        printCmdHelp(type)
    }
}

func printCmdHelp(_ type: Cmd.Type) {
    let meta = type.meta
    let name = meta.name == "macvision" ? "macvision" : "macvision \(meta.name)"

    // NAME — "macvision <cmd> - <one-line>"
    print("NAME:")
    print("    \(name) - \(meta.desc)")
    print("")

    // SYNOPSIS — one usage form per line.
    if !meta.synopsis.isEmpty {
        print("SYNOPSIS:")
        for line in meta.synopsis { print("    \(line)") }
        print("")
    }

    // DESCRIPTION — paragraph, then TIP / NOTE blocks.
    if !meta.longDesc.isEmpty || !meta.tips.isEmpty || !meta.notes.isEmpty {
        print("DESCRIPTION:")
        if !meta.longDesc.isEmpty {
            print("    \(meta.longDesc)")
        }
        for tip in meta.tips {
            print("    TIP:")
            print("        \(tip)")
        }
        for note in meta.notes {
            print("    NOTE:")
            print("        \(note)")
        }
        print("")
    }

    // SUBCOMMANDS
    if !meta.subcmds.isEmpty {
        print("SUBCOMMANDS:")
        for (n, subType) in meta.subcmds.sorted(by: { $0.key < $1.key }) {
            let subMeta = subType.meta
            let aliases = subMeta.alias.isEmpty ? "" : "|\(subMeta.alias.joined(separator: "|"))"
            print("    \(n)\(aliases)\t\(subMeta.desc)")
        }
        print("")
    }

    // OPTIONS
    if !meta.opts.isEmpty {
        print("OPTIONS:")
        for opt in meta.opts {
            let alias = opt.alias.map { "|\($0)" } ?? ""
            print("    \(opt.name)\(alias)\t\(opt.desc)")
        }
        print("")
    }

    // ARGS
    if !meta.args.isEmpty {
        print("ARGS:")
        for arg in meta.args {
            print("    \(arg.name)\t\(arg.desc)")
        }
        print("")
    }

    // TLDR — short desc + indented example command.
    if !meta.tldr.isEmpty {
        print("TLDR:")
        for (d, cmd) in meta.tldr {
            print("    \(d)")
            print("        \(cmd)")
        }
        print("")
    }
}

func cmdError(_ msg: String) -> Never {
    printJson(["ok": false, "error": msg])
    exit(1)
}
