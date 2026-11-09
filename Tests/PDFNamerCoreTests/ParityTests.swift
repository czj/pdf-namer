import Foundation
import Testing
@testable import PDFNamerCore

/// The Swift naming rules must give exactly what the original Python script gives
/// (fixture made by tools/gen_parity.py). One test case per fixture entry.
struct Fixture: Decodable, Sendable {
    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        let fields: [String: String], original: String, capture: String?, expected: String
        var testDescription: String { "\(fields["type"] ?? "") / \(fields["issuer"] ?? "") → \(expected)" }
    }
    struct Text: Decodable, Sendable, CustomTestStringConvertible {
        let s: String, expected: String
        var testDescription: String { s }
    }
    struct OptText: Decodable, Sendable, CustomTestStringConvertible {
        let s: String, expected: String?
        var testDescription: String { s }
    }
    struct FixCase: Decodable, Sendable, CustomTestStringConvertible {
        let s: String, sentence: Bool, expected: String
        var testDescription: String { "\(s) (\(sentence ? "phrase" : "nom"))" }
    }
    struct Trim: Decodable, Sendable, CustomTestStringConvertible {
        let s: String, limit: Int, expected: String
        var testDescription: String { "\(s) ≤ \(limit)" }
    }
    struct Cand: Decodable, Sendable, CustomTestStringConvertible {
        let text: String, expected: [String]
        var testDescription: String { String(text.prefix(60)) }
    }

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

private let fx = Fixture.shared
private let today = Day(iso: fx.today)!

@Suite struct `Parité avec le script Python` {
    @Test func `prompts identiques`() {
        #expect(Config.instructions == fx.instructions)
        #expect(Config.imageInstructions == fx.image_instructions)
        #expect(Config.types == fx.types)
        #expect(Config.imageTypes == fx.image_types)
    }

    @Test(arguments: fx.fix_case)
    func `casse`(_ c: Fixture.FixCase) {
        #expect(Naming.fixCase(c.s, sentence: c.sentence) == c.expected)
    }

    @Test(arguments: fx.sanitize)
    func `nettoyage`(_ c: Fixture.Text) {
        #expect(Naming.sanitize(c.s) == c.expected)
    }

    @Test(arguments: fx.parse_amount)
    func `montant`(_ c: Fixture.OptText) {
        #expect(Naming.parseAmount(c.s) == c.expected)
    }

    @Test(arguments: fx.trim_words)
    func `coupe aux mots`(_ c: Fixture.Trim) {
        #expect(Naming.trimWords(c.s, c.limit) == c.expected)
    }

    @Test(arguments: fx.date_candidates)
    func `dates candidates`(_ c: Fixture.Cand) {
        #expect(Candidates.dates(c.text, today: today) == c.expected)
    }

    @Test(arguments: fx.amount_candidates)
    func `montants candidats`(_ c: Fixture.Cand) {
        #expect(Candidates.amounts(c.text) == c.expected)
    }

    @Test(arguments: fx.build_filename)
    func `nom final`(_ c: Fixture.Case) {
        #expect(Naming.buildFilename(c.fields, original: c.original, captureDate: c.capture, today: today) == c.expected)
    }
}

@Test func `sauvegardes et fichiers déjà nommés`() {
    #expect(Files.backupName("x.pdf", day: Day(2026, 10, 1)!) == "RENAME BACKUP 2026-10-01 - x.pdf")
    #expect(Naming.isNamed("2026-11-05 - Facture EDF.pdf"))
    #expect(!Naming.isNamed("2026-11-05-Facture.pdf"))
    #expect("doc.final.pdf".pySplitExt == ("doc.final", ".pdf"))
    #expect(".hidden".pySplitExt == (".hidden", ""))
    #expect("/a/b.c/file".pySplitExt == ("/a/b.c/file", ""))
}

@Test func `page géante rendue à taille plafonnée`() throws {
    // A 5 m × 5 m page would be ~28 000 px at 144 dpi without the cap.
    let page = try #require(PDFKitTestPage.make(width: 14_400, height: 14_400))
    let img = try #require(Extractor.render(page, dpi: Config.ocrDPI))
    #expect(max(img.width, img.height) <= Int(Extractor.maxRenderSide))
}
