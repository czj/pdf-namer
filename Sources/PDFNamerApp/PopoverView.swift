import PDFNamerCore
import SwiftUI

/// The menu bar panel: drop zone and recent renames, or the current batch.
struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.items.isEmpty {
                DropZone(targeted: targeted)
                watchRow
                recentList
                footer
            } else {
                batch
            }
        }
        .padding(14)
        .frame(width: 400)
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return true
        } isTargeted: { targeted = $0 }
        .background {
            Button("Coller") { model.paste() }.keyboardShortcut("v").opacity(0).allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PDF Namer").font(.headline)
                Group {
                    switch model.engineState {
                    case .loading: Text("Chargement du modèle…")
                    case .ready: Text("Modèle Apple prêt · sur l’appareil")
                    case .unavailable(let why): Text(why).foregroundStyle(.red)
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let configError = model.configError {
                    Text(configError).font(.caption).foregroundStyle(.red).lineLimit(3)
                }
            }
            Spacer()
            Button {
                NSApp.activate()
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Réglages")
            .accessibilityLabel("Réglages")
        }
    }

    @ViewBuilder private var watchRow: some View {
        let active = model.settings.watchedFolders.filter(\.enabled)
        HStack(spacing: 8) {
            Image(systemName: "folder").foregroundStyle(active.isEmpty ? Color.secondary : Color.green)
            if active.isEmpty {
                Text("Aucun dossier surveillé")
                Spacer()
                Button("Ajouter…") { model.addFolder() }.buttonStyle(.link)
            } else {
                Text("Surveille ") + Text(ListFormatter.localizedString(byJoining: active.map(\.name))).bold()
                Spacer()
                Text("actif").font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var recentList: some View {
        if !model.recent.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Récemment renommés").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.bottom, 4)
                ForEach(model.recent.prefix(5)) { entry in
                    Button { model.reveal(URL(fileURLWithPath: entry.path)) } label: {
                        HStack(spacing: 10) {
                            FileBadge(ext: URL(fileURLWithPath: entry.path).pathExtension)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.newName).lineLimit(1).truncationMode(.middle)
                                Text("était « \(entry.oldName) » · \(entry.date.formatted(.relative(presentation: .named)))")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 4).padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .help("Afficher dans le Finder")
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Afficher les sauvegardes") { model.showBackups() }
            Spacer()
            Button("Quitter") { NSApp.terminate(nil) }
        }
        .buttonStyle(.link)
        .font(.callout)
        .padding(.top, 8)
        .overlay(alignment: .top) { Divider() }
    }

    private var batch: some View {
        let total = model.items.count, done = model.finishedCount
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.isBusy ? "Renommage · \(min(done + 1, total)) sur \(total)" : "Terminé · \(total) fichier(s)")
                        .font(.headline)
                    Spacer()
                }
                ProgressView(value: Double(done), total: Double(max(total, 1)))
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.items) { ItemCard(item: $0) }
                }
            }
            .frame(maxHeight: 380)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Toggle("Valider avant de renommer", isOn: Binding(
                    get: { model.settings.confirmBeforeRename },
                    set: { model.settings.confirmBeforeRename = $0 }))
                Spacer()
                if model.isBusy {
                    Button("Arrêter") { model.stop() }
                } else {
                    Button("Effacer") { model.clear() }.keyboardShortcut(.defaultAction)
                }
            }
            .font(.callout)
            .padding(.top, 10)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

struct DropZone: View {
    @Environment(AppModel.self) private var model
    var targeted: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc").font(.system(size: 30, weight: .light)).foregroundStyle(.tint)
            Text("Déposez des PDF ou des images").font(.callout.weight(.semibold))
            HStack(spacing: 4) {
                Text("ou")
                Button("choisissez des fichiers…") { model.chooseFiles() }.buttonStyle(.link)
                Text("· ⌘V pour coller")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(Color.accentColor.opacity(targeted ? 0.15 : 0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
    }
}

struct FileBadge: View {
    var ext: String

    var body: some View {
        let isPDF = ext.lowercased() == "pdf"
        RoundedRectangle(cornerRadius: 3)
            .fill(.background)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.quaternary))
            .overlay(alignment: .bottom) {
                Text(ext.uppercased().prefix(4))
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(isPDF ? Color.red : Color.blue)
                    .padding(.bottom, 3)
            }
            .frame(width: 26, height: 32)
    }
}
