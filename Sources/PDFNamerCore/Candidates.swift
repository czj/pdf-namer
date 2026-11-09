import Foundation

/// A calendar day, compared and printed like Python's datetime.date.
public struct Day: Comparable, Hashable, Sendable {
    public let y: Int, m: Int, d: Int

    public init?(_ y: Int, _ m: Int, _ d: Int) {
        guard (1...9999).contains(y), (1...12).contains(m), d >= 1, d <= Day.daysIn(y, m) else { return nil }
        self.y = y; self.m = m; self.d = d
    }

    /// "2026-11-09" → Day, nil if malformed or impossible.
    public init?(iso: String) {
        let p = iso.split(separator: "-")
        guard p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2,
              let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        self.init(y, m, d)
    }

    public static func today(_ cal: Calendar = .current) -> Day {
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return Day(c.year!, c.month!, c.day!)!
    }

    public init(_ date: Date, _ cal: Calendar = .current) {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self = Day(c.year!, c.month!, c.day!)!
    }

    public func adding(days n: Int, _ cal: Calendar = .current) -> Day {
        let date = cal.date(from: DateComponents(year: y, month: m, day: d))!
        return Day(cal.date(byAdding: .day, value: n, to: date)!, cal)
    }

    static func daysIn(_ y: Int, _ m: Int) -> Int {
        switch m {
        case 2: return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    public var iso: String { String(format: "%04d-%02d-%02d", y, m, d) }

    public static func < (a: Day, b: Day) -> Bool { (a.y, a.m, a.d) < (b.y, b.m, b.d) }
}

/// Dates and amounts found in the text, offered to the model as closed choices.
public enum Candidates {
    static let months = ["janv": 1, "fevr": 2, "mars": 3, "avri": 4, "mai": 5, "juin": 6, "juil": 7,
                         "aout": 8, "sept": 9, "octo": 10, "nove": 11, "dece": 12]
    static let dNum = Rx(#"\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})\b"#)
    static let dIso = Rx(#"\b((?:19|20)\d\d)-(\d\d)-(\d\d)\b"#)
    static let dTxt = Rx(#"\b(\d{1,2})(?:er)?\s+([a-zéû]{3,9})\.?\s+((?:19|20)\d\d)\b"#, [.caseInsensitive])
    static let aDec = Rx("(?<![\\d.,])(\\d{1,3}(?:[ \u{202F}\u{00A0}.]\\d{3})+|\\d+)[.,](\\d{2})(?![\\d.,%])")
    static let aKey = Rx("(total|montant|net à payer|à payer|ttc|payé|réglé|honoraires|solde|somme)",
                         [.caseInsensitive])
    static let aInt = Rx("(?:total|montant|net à payer|à payer|ttc|payé|honoraires)[^\\d\\n]{0,30}"
                         + "(\\d{1,3}(?:[ .]\\d{3})+|\\d+)(?![\\d.,])", [.caseInsensitive])
    static let groupSeps = Rx("[ .\u{202F}\u{00A0}]")
    static let intSeps = Rx("[ .]")

    /// Every plausible date in the text, ISO, in order of appearance.
    public static func dates(_ text: String, today: Day = .today()) -> [String] {
        var found: [String] = []
        func add(_ ys: String?, _ m: Int?, _ d: Int?) {
            guard let ys, var y = Int(ys), let m, let d else { return }
            if y < 100 { y += 2000 }
            guard let day = Day(y, m, d) else { return }
            if y >= 1990 && day <= today { found.append(day.iso) }  // an issue date is never in the future
        }
        for r in dNum.matches(text) {
            add(r.group(3, in: text), r.group(2, in: text).flatMap { Int($0) }, r.group(1, in: text).flatMap { Int($0) })
        }
        for r in dIso.matches(text) {
            add(r.group(1, in: text), r.group(2, in: text).flatMap { Int($0) }, r.group(3, in: text).flatMap { Int($0) })
        }
        for r in dTxt.matches(text) {
            let key = r.group(2, in: text)!.strippingAccents.lowercased().pySlice(nil, 4)
            if let month = months[key] {
                add(r.group(3, in: text), month, r.group(1, in: text).flatMap { Int($0) })
            }
        }
        return Array(unique(found).prefix(20))
    }

    static let curMarks: [(String, String)] = [("US$", "USD"), ("USD", "USD"), ("$", "USD"), ("€", "EUR"),
                                               ("EUR", "EUR"), ("£", "GBP"), ("GBP", "GBP"), ("CHF", "CHF"),
                                               ("CAD", "CAD"), ("¥", "JPY")]

    /// Currency written right next to an amount ('$76.07', '76,07 €', 'USD 76.07'), or nil.
    static func currencyNear(_ text: String, _ start: Int, _ end: Int) -> String? {
        let around = (text.pySlice(Swift.max(0, start - 6), start) + " " + text.pySlice(end, end + 6)).uppercased()
        return curMarks.first { around.contains($0.0) }?.1
    }

    /// Amounts in the text, 'NNN.NN CUR'; those next to 'total', 'TTC'... come first.
    public static func amounts(_ text: String) -> [String] {
        let upper = text.uppercased()
        var counts: [(String, Int)] = []  // insertion order, like the Python dict
        for (mark, code) in curMarks {
            let n = mark != "$" ? upper.pyCount(mark) : text.pyCount("$") - upper.pyCount("US$")
            if let i = counts.firstIndex(where: { $0.0 == code }) { counts[i].1 += n } else { counts.append((code, n)) }
        }
        var currency = "EUR"
        if counts.contains(where: { $0.1 != 0 }) {
            var best = counts[0]
            for c in counts.dropFirst() where c.1 > best.1 { best = c }
            currency = best.0
        }
        var keyed: [String] = [], others: [(Double, String)] = []
        for r in aDec.matches(text) {
            guard let whole = Int(groupSeps.sub(r.group(1, in: text)!, "")) else { continue }
            let value = "\(whole).\(r.group(2, in: text)!)"
            guard let v = Double(value), v != 0 else { continue }
            let start = r.range.location, end = r.range.location + r.range.length
            let item = "\(value) \(currencyNear(text, start, end) ?? currency)"
            if aKey.test(text.pySlice(Swift.max(0, start - 40), start)) { keyed.append(item) } else { others.append((v, item)) }
        }
        for r in aInt.matches(text) {  // whole-euro totals: "MONTANT DES HONORAIRES 1050"
            let g = r.range(at: 1)
            guard let whole = Int(intSeps.sub(r.group(1, in: text)!, "")) else { continue }
            keyed.append("\(whole).00 \(currencyNear(text, g.location, g.location + g.length) ?? currency)")
        }
        // Big amounts are likelier totals (stable sort, like Python's).
        let sorted = others.enumerated().sorted { a, b in
            a.element.0 != b.element.0 ? a.element.0 > b.element.0 : a.offset < b.offset
        }.map { $0.element.1 }
        return Array(unique(keyed + sorted).prefix(25))
    }

    static func unique(_ xs: [String]) -> [String] {
        var seen = Set<String>()
        return xs.filter { seen.insert($0).inserted }
    }
}
