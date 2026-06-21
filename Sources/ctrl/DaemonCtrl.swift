import Foundation

/// FIFO-based daemon plumbing.
///
/// Architecture decision (x-cmd style): IPC over named pipes (FIFO), not HTTP.
/// One request per NDJSON line on the request pipe; one response per line on
/// the response pipe. Both pipes are opened read/write so the daemon stays alive
/// across many short-lived clients without ever observing EOF.
enum DaemonCtrl {
    struct Config {
        var reqPath: String
        var resPath: String
    }

    /// Create the FIFOs if missing, then serve forever (until cancelled).
    static func run(_ cfg: Config) async throws {
        try ensureFifo(cfg.reqPath)
        try ensureFifo(cfg.resPath)

        guard
            let reqFH = FileHandle(forUpdatingAtPath: cfg.reqPath),
            let resFH = FileHandle(forUpdatingAtPath: cfg.resPath)
        else {
            throw VisionError.requestFailed("cannot open FIFOs at \(cfg.reqPath) / \(cfg.resPath)")
        }

        printJson(["ok": true, "event": "started", "req": cfg.reqPath, "res": cfg.resPath])
        fflush(stdout)

        while !Task.isCancelled {
            guard let line = readLine(from: reqFH), !line.isEmpty else { continue }
            let response = daemonHandleRequest(line)
            if let data = (response + "\n").data(using: .utf8) {
                resFH.write(data)
            }
        }
    }

    /// Create `path` as a FIFO (0600). Fail loudly if it exists as a regular file.
    static func ensureFifo(_ path: String) throws {
        var st = stat()
        if stat(path, &st) == 0 {
            if (st.st_mode & S_IFMT) != S_IFIFO {
                throw VisionError.requestFailed("\(path) exists and is not a FIFO")
            }
            return
        }
        if mkfifo(path, 0o600) != 0 {
            throw VisionError.requestFailed("mkfifo \(path) failed: \(String(cString: strerror(errno)))")
        }
    }

    /// Blocking line reader. FIFO reads block when empty; one byte at a time
    /// keeps NDJSON framing simple and correct.
    static func readLine(from fh: FileHandle) -> String? {
        var line = Data()
        while true {
            let chunk = fh.readData(ofLength: 1)
            if chunk.isEmpty {
                return line.isEmpty ? nil : String(data: line, encoding: .utf8)
            }
            if chunk[0] == 0x0A {
                return String(data: line, encoding: .utf8) ?? ""
            }
            line.append(chunk[0])
        }
    }
}
