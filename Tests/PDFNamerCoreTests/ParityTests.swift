import Foundation
import Testing
@testable import PDFNamerCore

/// The Swift naming rules must give exactly what ~/bin/pdf_namer.py gives
/// (fixture made by tools/gen_parity.py).
struct Fixture: Decodable {
    struct Case: Decodable {
        let fields: [String: String], original: String, capture: String?, expected: String
    }
    struct Text: Decodable { let s: String, expected: String }
    struct OptText: Decodable { let s: String, expected: String? }
    struct FixCase: Decodable { let s: String, sentence: Bool, expected: String }
    struct Trim: Decodable { let s: String, limit: Int, expected: String }
    struct Cand: Decodable { let text: String, expected: [String] }

    let today: String
    let instructions: String
    let image_instructions: String
    let types: [String]
    let image_types: [String]
    let build_filename: [Case]
    let fix_case: [FixCase]
    let sanitize: [Text]
    let parse_amount: [OptText]
    let trim_words: [Trim]
    let date_candidates: [Cand]
    let amount_candidates: [Cand]

    static let shared: Fixture = {
        let url = Bundle.module.url(forResource: "parity", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }()
}

let fx = Fixture.shared
let today = Day(iso: fx.today)!

@Test func prompts() {
    #expect(Config.instructions == fx.instructions)
    #expect(Config.imageInstructions == fx.image_instructions)
    #expect(Config.types == fx.types)
    #expect(Config.imageTypes == fx.image_types)
}

@Test func fixCase() {
    for c in fx.fix_case { #expect(Naming.fixCase(c.s, sentence: c.sentence) == c.expected, "\(c.s) / \(c.sentence)") }
}

@Test func sanitize() {
    for c in fx.sanitize { #expect(Naming.sanitize(c.s) == c.expected, "\(c.s)") }
}

@Test func parseAmount() {
    for c in fx.parse_amount { #expect(Naming.parseAmount(c.s) == c.expected, "\(c.s)") }
}

@Test func trimWords() {
    for c in fx.trim_words { #expect(Naming.trimWords(c.s, c.limit) == c.expected, "\(c.s) / \(c.limit)") }
}

@Test func dateCandidates() {
    for c in fx.date_candidates { #expect(Candidates.dates(c.text, today: today) == c.expected, "\(c.text)") }
}

@Test func amountCandidates() {
    for c in fx.amount_candidates { #expect(Candidates.amounts(c.text) == c.expected, "\(c.text)") }
}

@Test func buildFilename() {
    for c in fx.build_filename {
        let got = Naming.buildFilename(c.fields, original: c.original, captureDate: c.capture, today: today)
        #expect(got == c.expected, "\(c.fields) \(c.original) \(c.capture ?? "-")")
    }
}

@Test func backupAndNamed() {
    #expect(Files.backupName("x.pdf", day: Day(2026, 10, 1)!) == "RENAME BACKUP 2026-10-01 - x.pdf")
    #expect(Naming.isNamed("2026-11-05 - Facture EDF.pdf"))
    #expect(!Naming.isNamed("2026-11-05-Facture.pdf"))
    #expect("doc.final.pdf".pySplitExt == ("doc.final", ".pdf"))
    #expect(".hidden".pySplitExt == (".hidden", ""))
    #expect("/a/b.c/file".pySplitExt == ("/a/b.c/file", ""))
}
