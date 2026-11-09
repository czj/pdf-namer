import PDFNamerCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("Général", systemImage: "gearshape") }
            FoldersTab().tabItem { Label("Dossiers surveillés", systemImage: "folder") }
            CleanupTab().tabItem { Label("Sauvegardes et ménage", systemImage: "archivebox") }
        }
        .frame(width: 560, height: 400)
    }
}

private struct GeneralTab: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Valider chaque nom avant de renommer (fichiers déposés)", isOn: $model.settings.confirmBeforeRename)
                Toggle("Ouvrir au démarrage de la session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in model.launchAtLogin = on }
            }
            Section("Format du nom") {
                HStack(spacing: 4) {
                    ForEach(["Date", "Type", "Émetteur", "Détail", "Montant"], id: \.self) { part in
                        Text(part).font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                Text("Exemple : 2026-03-14 - Facture Kiné Durand - Séances de rééducation genou - 180.00 EUR.pdf")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Le montant n’apparaît que pour les factures, reçus, devis, avoirs, quittances et notes de frais. Les photos et captures d’écran prennent la date de prise de vue.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Modèle") {
                switch model.engineState {
                case .loading: Text("Chargement…")
                case .ready: Label("Modèle Apple sur l’appareil, prêt", systemImage: "checkmark.circle").foregroundStyle(.green)
                case .unavailable(let why): Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
            Section {
                LabeledContent("Configuration") {
                    HStack {
                        Text((UserConfig.directory.path as NSString).abbreviatingWithTildeInPath).foregroundStyle(.secondary)
                        Button("Afficher") { model.openConfigFolder() }
                    }
                }
                if model.localKeys.isEmpty {
                    Text("Ce Mac suit config.json.").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("Propre à ce Mac : \(model.localKeys.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Revenir à config.json") { model.resetLocalConfig() }
                    }
                }
                if let configError = model.configError {
                    Text(configError).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text("config.json est la configuration commune (à versionner avec tes dotfiles) ; l’app ne la modifie jamais. Ce que tu changes ici va dans config.local.json, qui ne concerne que ce Mac. La commande pdf-namer lit les deux.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = model.launchAtLogin }
    }
}

private struct FoldersTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                if model.settings.watchedFolders.isEmpty {
                    Text("Aucun dossier surveillé").foregroundStyle(.secondary)
                }
                ForEach($model.settings.watchedFolders) { $folder in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.tint)
                        Text(folder.path)
                        Spacer()
                        Toggle("Actif", isOn: $folder.enabled).labelsHidden().toggleStyle(.switch)
                        Button {
                            model.settings.watchedFolders.removeAll { $0.path == folder.path }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Retirer \(folder.name)")
                    }
                }
                Button("Ajouter un dossier…") { model.addFolder() }
            } footer: {
                Text("Les PDF et images qui arrivent dans ces dossiers sont renommés tout seuls, avec une notification. Les fichiers déjà présents et ceux déjà nommés « AAAA-MM-JJ - … » ne sont pas touchés.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CleanupTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                LabeledContent("Dossier des originaux") {
                    HStack {
                        Text(model.settings.backupDir).foregroundStyle(.secondary)
                        Button("Changer…", action: chooseBackupDir)
                    }
                }
                Picker("Supprimer les sauvegardes après", selection: $model.settings.backupMaxAgeDays) {
                    Text("6 mois").tag(180)
                    Text("1 an").tag(365)
                    Text("Jamais").tag(0)
                }
                Picker("Mettre à la corbeille les autres fichiers après", selection: $model.settings.expireMaxAgeDays) {
                    Text("Jamais").tag(0)
                    Text("6 mois").tag(180)
                    Text("1 an").tag(365)
                    Text("18 mois").tag(548)
                    Text("2 ans").tag(730)
                }
            } footer: {
                Text("Chaque original est copié sous le nom « RENAME BACKUP <date> - … » avant d’être renommé. Les autres fichiers de ce dossier (rangés là à la main) peuvent aussi être mis à la corbeille après un temps, d’après leur date d’ajout.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Faire le ménage maintenant") { Task { await model.runHousekeeping() } }
                    Spacer()
                    if let last = model.lastHousekeeping { Text(last).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseBackupDir() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { model.settings.backupDir = UserConfig.abbreviate(url.path) }
    }
}
