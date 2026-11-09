import Foundation

/// Turns the model's fields into "DATE - Type Émetteur - Détail - MONTANT" (port of build_filename).
public enum Naming {
    static let allowedChars = Rx(#"[^\w\s\-'.,]"#)
    static let multiSpace = Rx(#"\s{2,}"#)
    static let strayPunct = Rx(#"(?<!\d)[.,]|[.,](?!\d)"#)  // keep only decimal marks: 0.5 mg, 1,5 L
    static let innerDash = Rx(#"\s+-+\s+"#)
    static let datePrefix = Rx(#"^(\d{4}-\d{2}-\d{2})\s*-\s*"#)
    static let named = Rx(#"^\d{4}-\d{2}-\d{2} - "#)
    static let dateISO = Rx(#"^\d{4}-\d{2}-\d{2}$"#)
    static let nonLetters = Rx(#"[^\w]|\d"#)
    static let doctor = Rx(#"^(Docteur|Doctor|Dr\.?)\s+"#, [.caseInsensitive])
    static let amountRe = Rx(#"-?\d[\d\s.,']*"#)
    static let currencyRe = Rx(#"\b[A-Z]{3}\b"#)
    static let decimalTail = Rx(#"[.,](\d{1,2})$"#)
    static let amountJunk = Rx(#"[\s']"#)
    static let dotsCommas = Rx(#"[.,]"#)

    static let nullValues: Set<String> = ["none", "aucun", "aucune", "inconnu", "unknown", "n/a", "na", "-"]
    static let maxName = 110  // macOS allows 255; long enough to never cut a useful detail

    /// Document types that carry a total amount worth putting in the filename (substring match).
    static let amountTypes = ["factur", "avoir", "reçu", "devis", "quittance", "note de frais", "bon de commande",
                              "invoice", "receipt", "rechnung", "quittung"]
    /// Image types whose printed date is trusted over the shot date.
    static let documentTypes = amountTypes + [
        "relevé", "avis", "attestation", "certificat", "contrat", "avenant", "lettre", "courrier",
        "bulletin", "récépissé", "déclaration", "ticket", "ordonnance", "compte rendu", "convocation",
        "procès", "bilan", "rapport", "billet", "échéancier", "conditions"]
    static let currencySymbols: [(String, String)] = [("€", "EUR"), ("$", "USD"), ("£", "GBP"), ("¥", "JPY")]

    static let acronyms = Set("""
        APHP AP-HP URSSAF CPAM CAF DGFIP SNCF RATP IKEA FNAC BNP LCL CIC HSBC MAIF MAAF MACIF MATMUT
        AXA GMF SFR OVH IBAN RIB TVA CFE CVAE DSN DADS SIRET SIREN EURL SARL SASU CDI CDD RTT IRM
        PDF USB HDMI TTC HT ISBN AGIRC ARRCO PRAS ASSR BTS DELF TOEIC CESU PAJE APL ANTS ORIAS
        DREETS INPI INSEE AMELI MGEN EDF GRDF ENGIE BOUYGUES ORANGE
        """.pySplit)
    static let brands: Set<String> = ["ORANGE", "BOUYGUES", "ENGIE", "AMELI"]  // better as Orange, Engie...
    static let smallWords = Set("de du des d la le les l et à a au aux en pour par sur sous avec sans un une ou".pySplit)

    /// "2026-11-05 - …": already named by a previous run or by hand.
    public static func isNamed(_ filename: String) -> Bool { named.test(filename) }

    static func letters(_ w: String) -> String { nonLetters.sub(w, "") }

    static func recaseWord(_ w: String, first: Bool, sentence: Bool, allCaps: Bool = false) -> String {
        if let q = w.firstIndex(of: "'") {  // D'ENTRETIEN → d'Entretien / d'entretien
            var pre = String(w[..<q]), post = String(w[w.index(after: q)...])
            pre = first ? pre.pyCapitalize : pre.lowercased()
            if post.isEmpty { return pre }
            post = recaseWord(post, first: false, sentence: sentence, allCaps: allCaps)
            return "\(pre)'\(post)"
        }
        if w.pyStrip("-").contains("-") {
            return w.pySplit("-").enumerated()
                .map { recaseWord($1, first: first && $0 == 0, sentence: sentence, allCaps: allCaps) }
                .joined(separator: "-")
        }
        let l = letters(w)
        if l.isEmpty || !l.pyIsUpper || l.pyLen == 1 { return w }  // mixed case, lower case, numbers: trust as is
        if smallWords.contains(l.lowercased()) && !first { return w.lowercased() }
        if (acronyms.contains(l) && !brands.contains(l)) || (l.pyLen <= 3 && !(allCaps && sentence)) { return w }
        return first || !sentence ? w.pyCapitalize : w.lowercased()
    }

    /// Un-shout all-caps words. sentence: "Contrat d'entretien"; else "Pixel Up Studio".
    static func fixCase(_ s: String, sentence: Bool = false) -> String {
        let words = s.pySplit(" ")
        let shouty = words.contains { w in
            let l = letters(w)
            return l.pyLen >= 4 && l.pyIsUpper && !acronyms.contains(l)
        }
        guard shouty else { return s }
        let allCaps = letters(s).pyIsUpper  // whole field shouted: short words (UP, DU) are shouting too
        return words.enumerated()
            .map { recaseWord($1, first: $0 == 0, sentence: sentence, allCaps: allCaps) }
            .joined(separator: " ")
    }

    /// "1 234,50 €" / "EUR 2.99" / "2,99EUR" → "1234.50 EUR"; nil if unusable.
    static func parseAmount(_ raw: String) -> String? {
        let raw = raw.pyStrip
        guard let m = amountRe.first(raw) else { return nil }
        let num = amountJunk.sub((raw as NSString).substring(with: m.range), "").pyRStrip(".,")
        // Last separator followed by 1-2 digits is the decimal mark; others group thousands.
        let dec = decimalTail.first(num)
        let wholePart = dec.map { num.pySlice(nil, $0.range.location) } ?? num
        let whole = dotsCommas.sub(wholePart, "")
        let literal = dec.map { "\(whole).\($0.group(1, in: num)!)" } ?? whole
        guard isPyFloat(literal), let value = Double(literal), value != 0 else { return nil }
        var cur = currencySymbols.first { raw.contains($0.0) }?.1
        if cur == nil, let cm = currencyRe.first(raw.uppercased()) { cur = cm.group(0, in: raw.uppercased()) }
        guard let cur else { return nil }
        return String(format: "%.2f", value) + " " + cur
    }

    /// Only what Python's float() accepts from these digit runs: [-]digits[.digits].
    static func isPyFloat(_ s: String) -> Bool {
        s.range(of: #"^-?[0-9]*\.?[0-9]*$"#, options: .regularExpression) != nil && s.contains(where: \.isNumber)
    }

    /// Strip special chars and normalize whitespace for filename use.
    static func sanitize(_ s: String) -> String {
        var s = s.pyStrip.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "/", with: " ")
        s = allowedChars.sub(s, "")
        s = strayPunct.sub(s, "").replacingOccurrences(of: ",", with: ".")
        s = innerDash.sub(s, " ")  // " - " is our field separator: never inside a field
        return multiSpace.sub(s, " ").pyStrip(" -'").pySlice(nil, 80)
    }

    static func value(_ fields: [String: String], _ key: String) -> String {
        let v = sanitize(fields[key] ?? "")
        return nullValues.contains(v.lowercased()) ? "" : v
    }

    /// Cut at a word boundary, never ending on 'de', 'pour', 'et'...
    static func trimWords(_ s: String, _ limit: Int) -> String {
        var words = s.pySplit
        while !words.isEmpty && words.joined(separator: " ").pyLen > limit { words.removeLast() }
        while let last = words.last,
              smallWords.contains(last.lowercased().pyStrip("'")) || last.pyStrip("-").isEmpty {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    /// The model's raw answer, normalized like the Python "key: value" round trip: first line, trimmed.
    public static func normalize(_ raw: [String: String]) -> [String: String] {
        raw.mapValues { v in (v.components(separatedBy: .newlines).first ?? "").pyStrip }
    }

    /// File name without extension. captureDate (images only) wins for photos/screenshots
    /// and is the fallback otherwise.
    public static func buildFilename(_ raw: [String: String], original: String, captureDate: String? = nil,
                                     today: Day = .today()) -> String {
        let fields = normalize(raw)
        var docType = value(fields, "type")
        if docType.lowercased().hasPrefix("photo ou") { docType = "Photo" }  // model echoed "Photo ou Capture écran"
        docType = fixCase(docType, sentence: true).upperFirst
        var issuer = fixCase(value(fields, "issuer"))
        issuer = doctor.sub(issuer, "Dr ")
        issuer = issuer.pySplit.map { w in
            acronyms.contains(w.uppercased()) && !brands.contains(w.uppercased()) ? w.uppercased() : w
        }.joined(separator: " ")
        var detail = fixCase(value(fields, "detail"), sentence: true).upperFirst
        let lowerType = docType.lowercased()
        let amount = amountTypes.contains { lowerType.contains($0) } ? parseAmount(fields["amount"] ?? "") : nil

        // Don't repeat what is already said: "Facture EDF - EDF".
        if !detail.isEmpty && "\(docType) \(issuer)".lowercased().contains(detail.lowercased()) { detail = "" }

        let rawDate = (fields["date"] ?? "").pyStrip
        var modelDate: String? = dateISO.test(rawDate) ? rawDate : nil
        if let md = modelDate {
            // An issue date can't be in the future: deadline or misread.
            if let day = Day(iso: md) { if day > today { modelDate = nil } } else { modelDate = nil }
        }
        let date: String?
        let stem = original.pySplitExt.0
        if let m = datePrefix.first(stem) {
            date = m.group(1, in: stem)  // already dated by hand or a previous run: keep it
        } else if let captureDate, !documentTypes.contains(where: { lowerType.contains($0) }) {
            date = captureDate  // photo/screenshot: printed dates (posters, ads) aren't the file's date
        } else {
            date = modelDate ?? captureDate
        }

        let prefix = date.map { "\($0) - " } ?? ""
        let suffix = amount.map { " - \($0)" } ?? ""
        var head = [docType, issuer].filter { !$0.isEmpty }.joined(separator: " ")
        if head.isEmpty { head = "Document" }

        let room = maxName - prefix.pyLen - suffix.pyLen
        if head.pyLen > room - 10 {
            let t = trimWords(head, room - 10)
            head = t.isEmpty ? head.pySlice(nil, room - 10) : t
        }
        if !detail.isEmpty && head.pyLen + 3 + detail.pyLen > room {  // shorten the detail first, never mid-word
            detail = trimWords(detail, room - head.pyLen - 3)
        }
        var name = detail.isEmpty ? head : "\(head) - \(detail)"
        if name.pyLen > room { name = trimWords(name, room) }
        return prefix + name + suffix
    }

    /// Short labels for the UI chips: type, date, amount.
    public static func chips(_ raw: [String: String]) -> [String] {
        let f = normalize(raw)
        var out: [String] = []
        let t = value(f, "type")
        if !t.isEmpty { out.append(fixCase(t, sentence: true).upperFirst) }
        if let d = f["date"], let day = Day(iso: d) {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "fr_FR")
            fmt.dateFormat = "d MMM yyyy"
            out.append(fmt.string(from: Calendar.current.date(from: DateComponents(year: day.y, month: day.m, day: day.d))!))
        }
        if amountTypes.contains(where: { t.lowercased().contains($0) }), let a = parseAmount(f["amount"] ?? "") {
            out.append(a)
        }
        return out
    }
}
