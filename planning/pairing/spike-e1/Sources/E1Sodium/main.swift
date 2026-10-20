import Clibsodium
import Foundation

// E1: libsodium 1.0.22's edwards25519 operations, driven by Node.
//
// Each stdin line is one operation on 32- or 64-byte hex values, and each produces one stdout line:
//   uniform <u>        crypto_core_ed25519_from_uniform(u)     -> 32-byte point, or `error`
//   hash <h>           crypto_core_ed25519_from_hash(h), h 64B -> 32-byte point, or `error`
//   add <p> <q>        crypto_core_ed25519_add(p, q)           -> 32-byte point, or `error`
//   valid <p>          crypto_core_ed25519_is_valid_point(p)   -> `1` or `0`
// The first stdout line is `version <sodium_version_string()>`.
// Exit 2 on a malformed line. Node does the bookkeeping; libsodium does every group operation.

func decodeHex(_ text: Substring) -> [UInt8]? {
    guard text.count % 2 == 0 else { return nil }
    var out: [UInt8] = []
    var index = text.startIndex
    while index < text.endIndex {
        let next = text.index(index, offsetBy: 2)
        guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
        out.append(byte)
        index = next
    }
    return out
}

func encodeHex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

func malformed(_ line: String) -> Never {
    fputs("e1-sodium: malformed line: \(line)\n", stderr)
    exit(2)
}

guard sodium_init() >= 0 else {
    fputs("e1-sodium: sodium_init failed\n", stderr)
    exit(2)
}
print("version \(String(cString: sodium_version_string()))")

while let line = readLine() {
    let words = line.split(separator: " ")
    guard let op = words.first else { malformed(line) }
    let args = words.dropFirst().map { decodeHex($0) }
    if args.contains(where: { $0 == nil }) { malformed(line) }
    let values = args.map { $0! }

    switch (op, values.count) {
    case ("uniform", 1) where values[0].count == 32:
        var out = [UInt8](repeating: 0, count: 32)
        print(crypto_core_ed25519_from_uniform(&out, values[0]) == 0 ? encodeHex(out) : "error")
    case ("hash", 1) where values[0].count == 64:
        var out = [UInt8](repeating: 0, count: 32)
        print(crypto_core_ed25519_from_hash(&out, values[0]) == 0 ? encodeHex(out) : "error")
    case ("add", 2) where values[0].count == 32 && values[1].count == 32:
        var out = [UInt8](repeating: 0, count: 32)
        print(crypto_core_ed25519_add(&out, values[0], values[1]) == 0 ? encodeHex(out) : "error")
    case ("valid", 1) where values[0].count == 32:
        print(crypto_core_ed25519_is_valid_point(values[0]) == 1 ? "1" : "0")
    default:
        malformed(line)
    }
}
exit(0)
