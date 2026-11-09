import Foundation
import PDFNamerCore

// pdf-namer — same flags as ~/bin/pdf_namer.py:
//   pdf-namer <file> [--json]
//   pdf-namer --rename [--dry-run] [--force] [--backup-dir <dir>] <files...>

func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

let config: UserConfig
do { config = try UserConfig.load() } catch {
    err("✗ \(UserConfig.fileURL.path) illisible : \(error.localizedDescription)"); exit(1)
}
var files: [String] = [], json = false, rename = false, dryRun = false, force = false
var backupDir = config.backupURL
var customBackupDir = false  // trashing expired files only ever runs on the configured folder
var args = CommandLine.arguments.dropFirst()
while let a = args.popFirst() {
    switch a {
    case "--json": json = true
    case "--text":  // debug: what the model is given (text, date and amount candidates)
        for f in args {
            let ex = try Extractor.extract(URL(fileURLWithPath: f))
            let t = ex.text ?? ""
            print("── \(f)\n\(t)\n── dates: \(Candidates.dates(t))\n── montants: \(Candidates.amounts(t))")
        }
        exit(0)
    case "--rename": rename = true
    case "--dry-run": dryRun = true; rename = true
    case "--force": force = true
    case "--backup-dir":
        guard let d = args.popFirst() else { err("--backup-dir: dossier manquant"); exit(1) }
        backupDir = UserConfig.expand(d)
        customBackupDir = true
    case "-h", "--help":
        err("usage: pdf-namer <fichier> [--json] | --rename [--dry-run] [--force] [--backup-dir <dir>] <fichiers…>")
        exit(0)
    default: files.append(a)
    }
}
guard !files.isEmpty else {
    err("usage: pdf-namer <fichier> [--json] | --rename [--dry-run] [--force] [--backup-dir <dir>] <fichiers…>")
    exit(1)
}

let batch = rename || files.count > 1
func say(_ s: String) { if batch { print(s) } else { err(s) } }

var urls: [URL] = []
for f in files {
    let url = URL(fileURLWithPath: (f as NSString).expandingTildeInPath)
    if !FileManager.default.fileExists(atPath: url.path) { say("⚠ Introuvable : \(f)") }
    else if !Config.isSupported(url) { say("⚠ Ni PDF ni image : \(f)") }
    else { urls.append(url) }
}
// Already named ("2026-11-05 - …"): never touched in batch mode, so hand edits survive.
if rename && !force {
    let named = urls.filter { Naming.isNamed($0.lastPathComponent) }
    urls.removeAll { Naming.isNamed($0.lastPathComponent) }
    if !named.isEmpty {
        say("\(named.count) fichier(s) déjà nommé(s) (« AAAA-MM-JJ - … ») laissé(s) tel(s) quel(s) · --force pour les renommer quand même")
    }
    if urls.isEmpty { say("✓ Rien à renommer"); exit(0) }
}
guard !urls.isEmpty else { say("✗ Aucun PDF ni image valide"); exit(2) }

if batch { say("── PDF Namer · \(urls.count) fichier(s)\(dryRun ? " · simulation" : "") ──") }
let extractions = urls.map { url in Task { try await Namer.extract(url) } }  // OCR runs ahead of the model

let engine: Engine
do { engine = try Engine() } catch { say("✗ \(error.localizedDescription)"); exit(3) }
say("✓ Modèle Apple prêt")

if !batch {
    do {
        guard let s = try await Namer.suggest(urls[0], try await extractions[0].value, engine: engine) else {
            err("✗ Rien de lisible dans ce fichier"); exit(2)
        }
        if json {
            let out: [String: String] = ["original": urls[0].lastPathComponent, "suggested": s.name, "path": urls[0].path]
            let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            print(String(decoding: data, as: UTF8.self))
        } else {
            print((s.name as NSString).deletingPathExtension)
        }
    } catch {
        err("✗ \(error.localizedDescription)"); exit(2)
    }
    exit(0)
}

let report = Files.housekeeping(backupDir, dryRun: dryRun, backupMaxAgeDays: config.backupMaxAge,
                                expireMaxAgeDays: customBackupDir ? nil : config.expireMaxAge)
let would = dryRun ? "seraient " : ""
if !report.purged.isEmpty {
    print("✓ \(report.purged.count) sauvegarde(s) de plus de \(config.backupMaxAgeDays) jours \(would)supprimée(s)")
}
if !report.trashed.isEmpty {
    print("✓ \(report.trashed.count) élément(s) de plus de \(config.expireMaxAgeDays / 30) mois \(would)mis à la corbeille :")
    for t in report.trashed { print("    · \(t)") }
}
print()

var renamed = 0, unchanged = 0, skipped = 0, errors = 0
let start = Date()
for (n, url) in urls.enumerated() {
    let filename = url.lastPathComponent, t0 = Date()
    print("\(n + 1)/\(urls.count) avant    \(filename)")
    do {
        guard let s = try await Namer.suggest(url, try await extractions[n].value, engine: engine) else {
            print("  – ignoré   rien de lisible\n"); skipped += 1; continue
        }
        let took = String(format: "%.1fs", Date().timeIntervalSince(t0))
        if s.name == filename { print("  = inchangé déjà bien nommé \(took)\n"); unchanged += 1; continue }
        if dryRun {
            print("  ○ proposé  \(s.name) \(took)\n")
        } else {
            let final = try Files.rename(url, to: s.name, backupDir: backupDir)
            print("  ✓ après    \(final.lastPathComponent) \(took)\n")
        }
        renamed += 1
    } catch {
        print("  ✗ erreur   \(error.localizedDescription)\n"); errors += 1
    }
}
let stats = [(renamed, dryRun ? "à renommer" : "renommé(s)"), (unchanged, "inchangé(s)"),
             (skipped, "ignoré(s)"), (errors, "erreur(s)")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
print(String(repeating: "─", count: 60))
print("\(stats.isEmpty ? "Rien à faire" : stats.joined(separator: " · "))  · \(urls.count) fichier(s) en \(Int(Date().timeIntervalSince(start).rounded()))s\(dryRun ? " · simulation, rien n’a été modifié" : "")")
