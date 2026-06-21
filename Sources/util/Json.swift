import Foundation

func printJson(_ data: [String: Any]) {
    do {
        let d = try JSONSerialization.data(
            withJSONObject: data,
            options: [.sortedKeys, .fragmentsAllowed]
        )
        if let s = String(data: d, encoding: .utf8) {
            print(s)
        } else {
            print("{\"ok\":false,\"error\":\"encode failed\"}")
        }
    } catch {
        print("{\"ok\":false,\"error\":\"\(error.localizedDescription)\"}")
    }
}

/// Base64-encode raw bytes for compact embedding in JSON output (e.g. feature-print vectors).
func base64Bytes(_ data: Data) -> String {
    data.base64EncodedString()
}
