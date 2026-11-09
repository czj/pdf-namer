import Foundation
import FoundationModels

public enum EngineError: LocalizedError {
    case unavailable(String)
    case model(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "Modèle Apple indisponible (\(reason)). Réglages → Apple Intelligence et Siri doit être activé."
        case .model(let msg): return "modèle Apple : \(msg)"
        }
    }
}

/// Apple's on-device model (FoundationModels) filling a constrained form.
public final class Engine: @unchecked Sendable {
    let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 250)
    let tmp: URL

    public init() throws {
        guard case .available = model.availability else { throw EngineError.unavailable("\(model.availability)") }
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-namer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: tmp) }

    struct Field { let name: String, description: String, choices: [String]? }

    enum Failure: Error { case context(String), guardrail(String), other(String) }

    /// The model's fields (type, issuer, date, detail, amount) for one extracted file.
    public func ask(_ ex: Extracted, isImage: Bool) async throws -> [String: String] {
        var imageURL: URL?
        if let image = ex.image {
            let url = tmp.appendingPathComponent("\(UUID().uuidString).png")
            try Extractor.writePNG(image, to: url)
            imageURL = url
        }
        defer { if let imageURL { try? FileManager.default.removeItem(at: imageURL) } }

        let text = ex.text ?? ""
        let dates = Candidates.dates(text), amounts = Candidates.amounts(text)
        let fields = [
            Field(name: "type", description: "Nature du document",
                  choices: isImage ? Config.imageTypes : Config.types),
            Field(name: "issuer", description: "Qui a écrit le document, forme courte, ou aucun", choices: nil),
            Field(name: "date", description: "Date d'émission du document (AAAA-MM-JJ), ou aucun",
                  choices: dates.isEmpty ? nil : dates + ["aucun"]),
            Field(name: "detail", description: "2 à 6 mots sur l'objet précis", choices: nil),
            Field(name: "amount", description: "Montant total TTC (factures, reçus, devis...), ou aucun",
                  choices: amounts + ["aucun"]),
        ]
        let instructions = isImage ? Config.imageInstructions : Config.instructions
        let body = ex.text?.pyStrip ?? "(aucun texte lisible, utilise l'image)"
        // Fallbacks: the model may refuse a page image or overflow its 8k context.
        var attempts: [(URL?, String)] = imageURL != nil
            ? [(imageURL, body), (nil, body), (nil, body.pySlice(nil, 2000))]
            : [(nil, body), (nil, body.pySlice(nil, 2000))]
        if ex.text == nil && imageURL != nil { attempts = [(imageURL, body)] }

        var last = "?"
        for (image, txt) in attempts {
            do {
                return try await respond(instructions: instructions, prompt: "Texte du document:\n---\n\(txt)\n---",
                                         image: image, fields: fields)
            } catch Failure.context(let msg), Failure.guardrail(let msg) {
                last = msg
            } catch Failure.other(let msg) {
                last = msg
                break
            }
        }
        throw EngineError.model(last)
    }

    func respond(instructions: String, prompt: String, image: URL?, fields: [Field]) async throws -> [String: String] {
        do {
            let properties = fields.map { f in
                DynamicGenerationSchema.Property(
                    name: f.name, description: f.description,
                    schema: f.choices.map { DynamicGenerationSchema(type: String.self, guides: [.anyOf($0)]) }
                        ?? DynamicGenerationSchema(type: String.self))
            }
            let schema = try GenerationSchema(
                root: DynamicGenerationSchema(name: "Document", properties: properties), dependencies: [])
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response: LanguageModelSession.Response<GeneratedContent>
            if let image {
                response = try await session.respond(schema: schema, options: options) {
                    Attachment(imageURL: image)
                    prompt
                }
            } else {
                response = try await session.respond(to: prompt, schema: schema, options: options)
            }
            var out: [String: String] = [:]
            for f in fields { out[f.name] = (try? response.content.value(String.self, forProperty: f.name)) ?? "aucun" }
            return out
        } catch let error as LanguageModelError {
            switch error {
            case .contextSizeExceeded: throw Failure.context("\(error)")
            case .guardrailViolation, .refusal, .unsupportedTranscriptContent: throw Failure.guardrail("\(error)")
            default: throw Failure.other("\(error)")
            }
        } catch {
            throw Failure.other("\(error)")
        }
    }
}
