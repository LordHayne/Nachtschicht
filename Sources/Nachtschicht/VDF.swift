import Foundation

/// Minimal parser for Valve's KeyValues text format (appmanifest_*.acf, libraryfolders.vdf, localconfig.vdf).
/// Keys are stored lowercased because Steam isn't consistent about casing ("appid" vs "appID").
indirect enum VDF {
    case string(String)
    case object([String: VDF])

    subscript(key: String) -> VDF? {
        if case .object(let dict) = self { return dict[key.lowercased()] }
        return nil
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var object: [String: VDF]? {
        if case .object(let d) = self { return d }
        return nil
    }

    static func parse(_ text: String) -> VDF? {
        var parser = VDFParser(Array(text.unicodeScalars))
        return parser.parseObjectBody()
    }

    static func parse(contentsOf url: URL) -> VDF? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }
}

private enum VDFToken {
    case str(String)
    case open
    case close
}

private struct VDFParser {
    private let s: [Unicode.Scalar]
    private var i = 0

    init(_ scalars: [Unicode.Scalar]) { s = scalars }

    /// Reads `key value` / `key { ... }` pairs until a closing brace or end of input.
    mutating func parseObjectBody() -> VDF? {
        var dict: [String: VDF] = [:]
        while let token = next() {
            switch token {
            case .close:
                return .object(dict)
            case .open:
                return nil
            case .str(let key):
                guard let valueToken = next() else { return .object(dict) }
                switch valueToken {
                case .str(let value):
                    dict[key.lowercased()] = .string(value)
                case .open:
                    guard let nested = parseObjectBody() else { return nil }
                    dict[key.lowercased()] = nested
                case .close:
                    return .object(dict)
                }
            }
        }
        return .object(dict)
    }

    private func isSpace(_ c: Unicode.Scalar) -> Bool {
        c == " " || c == "\t" || c == "\n" || c == "\r"
    }

    private mutating func next() -> VDFToken? {
        while i < s.count {
            let c = s[i]
            if isSpace(c) { i += 1; continue }

            // Line comment
            if c == "/", i + 1 < s.count, s[i + 1] == "/" {
                while i < s.count, s[i] != "\n" { i += 1 }
                continue
            }
            // Platform conditionals like [$WIN32] – ignored
            if c == "[" {
                while i < s.count, s[i] != "]" { i += 1 }
                i += 1
                continue
            }
            if c == "{" { i += 1; return .open }
            if c == "}" { i += 1; return .close }

            if c == "\"" {
                i += 1
                var out = String.UnicodeScalarView()
                while i < s.count, s[i] != "\"" {
                    if s[i] == "\\", i + 1 < s.count {
                        let n = s[i + 1]
                        switch n {
                        case "n": out.append("\n")
                        case "t": out.append("\t")
                        default: out.append(n)
                        }
                        i += 2
                    } else {
                        out.append(s[i])
                        i += 1
                    }
                }
                i += 1 // closing quote
                return .str(String(out))
            }

            // Unquoted token
            var out = String.UnicodeScalarView()
            while i < s.count {
                let ch = s[i]
                if isSpace(ch) || ch == "{" || ch == "}" || ch == "\"" { break }
                out.append(ch)
                i += 1
            }
            return .str(String(out))
        }
        return nil
    }
}
