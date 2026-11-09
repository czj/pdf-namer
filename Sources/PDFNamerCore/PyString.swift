import Foundation

// Small helpers that reproduce Python's string semantics, so the naming rules
// ported from pdf_namer.py give byte-identical results. Lengths and slices are
// in UTF-16 units (= Python code points for everything outside emoji).

/// A compiled ICU regex (NSRegularExpression supports the look-behinds the Python rules use).
struct Rx {
    let re: NSRegularExpression

    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        re = try! NSRegularExpression(pattern: pattern, options: options)
    }

    func matches(_ s: String) -> [NSTextCheckingResult] {
        re.matches(in: s, range: NSRange(location: 0, length: s.utf16.count))
    }

    func first(_ s: String) -> NSTextCheckingResult? {
        re.firstMatch(in: s, range: NSRange(location: 0, length: s.utf16.count))
    }

    func test(_ s: String) -> Bool { first(s) != nil }

    /// Python re.sub(pattern, literal, s).
    func sub(_ s: String, _ replacement: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: s.utf16.count),
                                    withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }
}

extension NSTextCheckingResult {
    /// Text of capture group `i`, or nil when it did not participate.
    func group(_ i: Int, in s: String) -> String? {
        let r = range(at: i)
        guard r.location != NSNotFound else { return nil }
        return (s as NSString).substring(with: r)
    }
}

extension String {
    var pyLen: Int { utf16.count }

    /// Python s[a:b] with clamping and negative indices.
    func pySlice(_ a: Int? = nil, _ b: Int? = nil) -> String {
        let n = pyLen
        func norm(_ i: Int) -> Int { i < 0 ? Swift.max(0, n + i) : Swift.min(i, n) }
        let lo = norm(a ?? 0), hi = norm(b ?? n)
        guard hi > lo else { return "" }
        return (self as NSString).substring(with: NSRange(location: lo, length: hi - lo))
    }

    /// Python s.strip() (whitespace).
    var pyStrip: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Python s.strip(chars).
    func pyStrip(_ chars: String) -> String {
        let set = Set(chars)
        var cs = Substring(self)
        while let f = cs.first, set.contains(f) { cs = cs.dropFirst() }
        while let l = cs.last, set.contains(l) { cs = cs.dropLast() }
        return String(cs)
    }

    /// Python s.rstrip(chars).
    func pyRStrip(_ chars: String) -> String {
        let set = Set(chars)
        var cs = Substring(self)
        while let l = cs.last, set.contains(l) { cs = cs.dropLast() }
        return String(cs)
    }

    /// Python s.split() (runs of whitespace, no empty items).
    var pySplit: [String] { split(whereSeparator: { $0.isWhitespace }).map(String.init) }

    /// Python s.split(" ") (keeps empty items).
    func pySplit(_ sep: String) -> [String] { components(separatedBy: sep) }

    /// Python s.isupper(): at least one cased character and none lowercase.
    var pyIsUpper: Bool {
        var cased = false
        for u in unicodeScalars {
            switch u.properties.generalCategory {
            case .lowercaseLetter, .titlecaseLetter: return false
            case .uppercaseLetter: cased = true
            default: if u.properties.isLowercase { return false }
            }
        }
        return cased
    }

    /// Python s.capitalize(): first character upper, the rest lower.
    var pyCapitalize: String {
        guard let f = first else { return self }
        return String(f).uppercased() + dropFirst().lowercased()
    }

    /// Python s[:1].upper() + s[1:].
    var upperFirst: String {
        guard let f = first else { return self }
        return String(f).uppercased() + dropFirst()
    }

    /// Python s.count(sub): non-overlapping occurrences.
    func pyCount(_ sub: String) -> Int { components(separatedBy: sub).count - 1 }

    /// Accents removed (NFD, combining marks dropped).
    var strippingAccents: String {
        String(String.UnicodeScalarView(decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { $0.properties.generalCategory != .nonspacingMark }))
    }

    /// Python os.path.splitext(s) on a file name: (root, ".ext"); leading dots are not an extension.
    var pySplitExt: (String, String) {
        let ns = self as NSString
        let slash = ns.range(of: "/", options: .backwards).location
        let nameStart = slash == NSNotFound ? 0 : slash + 1
        let dot = ns.range(of: ".", options: .backwards).location
        guard dot != NSNotFound, dot > nameStart else { return (self, "") }
        // Only dots before it in the name → hidden file, no extension.
        let lead = ns.substring(with: NSRange(location: nameStart, length: dot - nameStart))
        guard lead.contains(where: { $0 != "." }) else { return (self, "") }
        return (ns.substring(to: dot), ns.substring(from: dot))
    }
}
