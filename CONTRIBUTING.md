# Contributing to macvision

Thanks for your interest! macvision is a small, focused macOS vision CLI. Please read this short guide before opening an issue or PR.

## Reporting issues

Open a [GitHub issue](../../issues) and include:

- macOS version
- macvision version (build it from source, or note the commit)
- The exact command you ran
- Expected vs actual output
- If relevant, the full JSON output

## Feature requests

macvision deliberately stays small. We only add things that are hard or slow to do from shell, Python, or AppleScript, and that map onto a `Vision` framework request. If your idea fits, open an issue and explain the use case.

## Building from source

Requires Swift 5.10+ / macOS 13+.

```sh
git clone https://github.com/ljh-sh/macvision
cd macvision
swift build -c release
```

The binary will be at `.build/release/macvision`.

## Running tests

```sh
swift test
```

> Tests use `XCTest`, which requires a full Xcode install (not just Command Line Tools). On CI this runs on `macos-14` with Xcode selected.

## Pull requests

- Keep the change minimal and focused.
- Follow the existing Swift style (compact JSON output, the in-repo `Cmd` framework, no external dependencies).
- Update README / changelog / ROADMAP if your change affects CLI behavior.
- Do not add heavy dependencies — `Vision`, `CoreGraphics`, `CoreImage`, `CoreVideo`, and `AppKit` are all system frameworks and that is the entire dependency surface.

All changes must be submitted through a pull request and approved by a repository admin before merging.

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
