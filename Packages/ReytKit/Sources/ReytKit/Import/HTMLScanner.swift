import Foundation

/// A token from the tolerant HTML scanner.
enum HTMLToken: Equatable {
    case open(name: String, attributes: [String: String])
    case close(name: String)
    case text(String)
}

/// A small, forgiving HTML tokenizer for the Cocoa HTML Writer output of Apple Journal exports (A6).
/// It only splits text from tags. It never evaluates anything: `<script>` and `<style>` content is skipped
/// entirely, comments and doctypes are dropped, and nothing is fetched. No WebKit, no attributed-string HTML import.
enum HTMLScanner {
    private static let lt = UInt8(ascii: "<")
    private static let gt = UInt8(ascii: ">")
    private static let slash = UInt8(ascii: "/")
    private static let bang = UInt8(ascii: "!")
    private static let question = UInt8(ascii: "?")
    private static let equals = UInt8(ascii: "=")
    private static let dquote = UInt8(ascii: "\"")
    private static let squote = UInt8(ascii: "'")

    static func tokens(_ bytes: [UInt8]) -> [HTMLToken] {
        var out: [HTMLToken] = []
        var text: [UInt8] = []
        var i = 0
        let n = bytes.count

        func flushText() {
            guard !text.isEmpty else { return }
            out.append(.text(HTMLEntities.decode(String(decoding: text, as: UTF8.self))))
            text.removeAll(keepingCapacity: true)
        }

        while i < n {
            let b = bytes[i]
            guard b == lt else {
                text.append(b)
                i += 1
                continue
            }
            let next = i + 1 < n ? bytes[i + 1] : 0
            if next == bang || next == question {
                flushText()
                if matches(bytes, at: i, "<!--") {
                    i = indexAfter(bytes, "-->", from: i + 4) ?? n
                } else {
                    i = (bytes[i...].firstIndex(of: gt)).map { $0 + 1 } ?? n
                }
            } else if next == slash, i + 2 < n, isLetter(bytes[i + 2]) {
                flushText()
                var j = i + 2
                let start = j
                while j < n, isNameByte(bytes[j]) { j += 1 }
                let name = lowercased(bytes[start..<j])
                i = (bytes[j...].firstIndex(of: gt)).map { $0 + 1 } ?? n
                out.append(.close(name: name))
            } else if isLetter(next) {
                flushText()
                var j = i + 1
                let start = j
                while j < n, isNameByte(bytes[j]) { j += 1 }
                let name = lowercased(bytes[start..<j])
                var attributes: [String: String] = [:]
                j = parseAttributes(bytes, from: j, into: &attributes)
                out.append(.open(name: name, attributes: attributes))
                i = j
                if name == "script" || name == "style" {
                    // Content is never read, let alone run.
                    i = indexAfterClosingTag(bytes, name: name, from: i) ?? n
                    out.append(.close(name: name))
                }
            } else {
                text.append(b)
                i += 1
            }
        }
        flushText()
        return out
    }

    /// Parses attributes up to and including the closing `>`; returns the index after it.
    private static func parseAttributes(_ bytes: [UInt8], from start: Int, into attrs: inout [String: String]) -> Int {
        var j = start
        let n = bytes.count
        while j < n {
            while j < n, isSpace(bytes[j]) || bytes[j] == slash { j += 1 }
            guard j < n else { return n }
            if bytes[j] == gt { return j + 1 }
            let nameStart = j
            while j < n, !isSpace(bytes[j]), bytes[j] != equals, bytes[j] != gt, bytes[j] != slash { j += 1 }
            let name = lowercased(bytes[nameStart..<j])
            if j == nameStart {  // a stray byte: step over it so the loop always advances
                j += 1
                continue
            }
            while j < n, isSpace(bytes[j]) { j += 1 }
            var value = ""
            if j < n, bytes[j] == equals {
                j += 1
                while j < n, isSpace(bytes[j]) { j += 1 }
                if j < n, bytes[j] == dquote || bytes[j] == squote {
                    let quote = bytes[j]
                    j += 1
                    let vStart = j
                    while j < n, bytes[j] != quote { j += 1 }
                    value = String(decoding: bytes[vStart..<min(j, n)], as: UTF8.self)
                    if j < n { j += 1 }
                } else {
                    let vStart = j
                    while j < n, !isSpace(bytes[j]), bytes[j] != gt { j += 1 }
                    value = String(decoding: bytes[vStart..<j], as: UTF8.self)
                }
            }
            if attrs[name] == nil { attrs[name] = HTMLEntities.decode(value) }
        }
        return n
    }

    private static func isLetter(_ b: UInt8) -> Bool { (b >= 65 && b <= 90) || (b >= 97 && b <= 122) }
    private static func isNameByte(_ b: UInt8) -> Bool {
        isLetter(b) || (b >= 48 && b <= 57) || b == UInt8(ascii: "-") || b == UInt8(ascii: ":")
    }
    private static func isSpace(_ b: UInt8) -> Bool { b == 32 || b == 9 || b == 10 || b == 13 || b == 12 }

    private static func lowercased(_ slice: ArraySlice<UInt8>) -> String {
        String(decoding: slice.map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }, as: UTF8.self)
    }

    private static func matches(_ bytes: [UInt8], at i: Int, _ literal: String) -> Bool {
        let lit = Array(literal.utf8)
        guard i + lit.count <= bytes.count else { return false }
        return Array(bytes[i..<(i + lit.count)]) == lit
    }

    private static func indexAfter(_ bytes: [UInt8], _ literal: String, from: Int) -> Int? {
        let lit = Array(literal.utf8)
        guard !lit.isEmpty, bytes.count >= lit.count, from <= bytes.count - lit.count else { return nil }
        var i = from
        while i <= bytes.count - lit.count {
            if bytes[i] == lit[0], Array(bytes[i..<(i + lit.count)]) == lit { return i + lit.count }
            i += 1
        }
        return nil
    }

    /// Index just after the `>` of the next `</name` (case-insensitive), or nil when there is none.
    private static func indexAfterClosingTag(_ bytes: [UInt8], name: String, from: Int) -> Int? {
        let lit = Array("</\(name)".utf8)
        var i = from
        while i + lit.count <= bytes.count {
            if bytes[i] == lt, bytes[i + 1] == slash {
                let candidate = lowercased(bytes[i..<(i + lit.count)])
                if candidate == "</\(name)" {
                    return (bytes[(i + lit.count)...].firstIndex(of: gt)).map { $0 + 1 } ?? bytes.count
                }
            }
            i += 1
        }
        return nil
    }
}

enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "hellip": "\u{2026}", "ndash": "\u{2013}", "mdash": "\u{2014}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "copy": "\u{00A9}",
    ]

    /// Decodes named (a small set) and numeric entities; anything unrecognised is left as written.
    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var index = s.startIndex
        while index < s.endIndex {
            let ch = s[index]
            if ch == "&", let semi = s[index...].prefix(12).firstIndex(of: ";") {
                let body = s[s.index(after: index)..<semi]
                if let decoded = decodeBody(body) {
                    out += decoded
                    index = s.index(after: semi)
                    continue
                }
            }
            out.append(ch)
            index = s.index(after: index)
        }
        return out
    }

    private static func decodeBody(_ body: Substring) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let v = value, let scalar = Unicode.Scalar(v) else { return nil }
            return String(Character(scalar))
        }
        return named[String(body)]
    }
}
