import Foundation

/// macvision entry point.
///
/// Vision's `VNImageRequestHandler.perform(_:)` is synchronous and needs no run
/// loop, so — unlike audio-framework tools — we do not spin up an `NSApplication`.
/// AppKit is only touched lazily (clipboard) inside `ImageLoader`.
@main
struct Entry {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        do {
            try await runCmd(MacvisionRoot.self, args)
        } catch {
            printJson(["ok": false, "error": error.localizedDescription])
            exit(1)
        }
    }
}
