import PDFNamerCore
import SwiftUI

/// One file in the batch: progress, then the new name with Modifier / Annuler.
struct ItemCard: View {
    @Environment(AppModel.self) private var model
    let item: Item
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusLine
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(item.phase == .waiting ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            icon.frame(width: 12, height: 12)
            Text(item.originalName)
                .strikethrough(item.phase == .done)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(status)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var icon: some View {
        switch item.phase {
        case .waiting: Image(systemName: "clock")
        case .reading, .analyzing: ProgressView().controlSize(.mini)
        case .done: Image(systemName: "checkmark").foregroundStyle(.green)
        case .proposed: Image(systemName: "questionmark.circle").foregroundStyle(.orange)
        case .unchanged: Image(systemName: "equal")
        case .cancelled: Image(systemName: "arrow.uturn.backward")
        case .skipped: Image(systemName: "minus").foregroundStyle(.orange)
        case .failed: Image(systemName: "xmark").foregroundStyle(.red)
        }
    }

    private var status: String {
        switch item.phase {
        case .waiting: return "en attente"
        case .reading: return "lecture…"
        case .analyzing: return "analyse…"
        case .proposed: return "à valider"
        case .unchanged: return "déjà bien nommé"
        case .cancelled: return "annulé"
        case .skipped(let why): return why
        case .failed: return "erreur"
        case .done: return item.took.map { String(format: "%.1f s", $0) } ?? ""
        }
    }

    @ViewBuilder private var content: some View {
        switch item.phase {
        case .reading, .analyzing:
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 220, height: 12)
        case .failed(let msg):
            Text(msg).font(.caption).foregroundStyle(.red).textSelection(.enabled)
        case .proposed, .done:
            if editing {
                HStack {
                    TextField("Nouveau nom", text: $draft).textFieldStyle(.roundedBorder)
                        .onSubmit(commit)
                    Button("OK", action: commit).keyboardShortcut(.defaultAction)
                    Button("Annuler") { editing = false }
                }
                .font(.callout)
            } else {
                Text(displayName).font(.callout.weight(.semibold)).textSelection(.enabled)
                actions
            }
        default:
            EmptyView()
        }
    }

    private var displayName: String {
        item.phase == .proposed ? item.suggestion?.name ?? "" : item.url.lastPathComponent
    }

    private var actions: some View {
        HStack(spacing: 6) {
            ForEach(item.suggestion?.chips ?? [], id: \.self) { chip in
                Text(chip)
                    .font(.caption2)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            if item.phase == .proposed {
                Button("Modifier", action: startEditing)
                Button("Ignorer") { model.skip(item) }
                Button("Renommer") { model.apply(item, name: displayName) }.buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Button("Modifier", action: startEditing)
                Button("Annuler") { model.undo(item) }
                Button("Afficher") { model.reveal(item.url) }
            }
        }
        .buttonStyle(.link)
        .font(.caption)
    }

    private func startEditing() {
        draft = (displayName as NSString).deletingPathExtension
        editing = true
    }

    private func commit() {
        editing = false
        model.apply(item, name: draft)
    }
}
