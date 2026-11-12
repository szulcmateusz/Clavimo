import AppKit
import ClavimoCore
import SwiftUI
import UniformTypeIdentifiers

/// Export, import with a preview of the changes, and restoring the
/// previous version of the configuration.
struct BackupSection: View {
    @Bindable var editor: ConfigEditor
    @State private var preview: Preview?
    @State private var message: String?
    @State private var pasting = false

    struct Preview: Identifiable {
        let id = UUID()
        let title: String
        let document: ConfigDocument
    }

    var body: some View {
        Section {
            HStack {
                Button(String(localized: "Export...")) { export() }
                Button(String(localized: "Import...")) { importFile() }
                Button(String(localized: "Paste Rules...")) { pasting = true }
                Spacer()
                Button(String(localized: "Restore Previous Version...")) {
                    if let backup = editor.backupDocument {
                        preview = Preview(title: String(localized: "Restore the previous version"), document: backup)
                    } else {
                        message = String(localized: "There is no previous version yet. One is kept every time you change a rule.")
                    }
                }
            }
            if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
        } header: {
            Text(String(localized: "Backup and Import"))
        } footer: {
            Text(String(localized: "Exported files contain your rules, app identifiers and device IDs, never anything you typed. Importing shows the changes before anything is applied.")).formFooterStyle()
        }
        .sheet(isPresented: $pasting) {
            PasteRulesView(editor: editor) { result in message = result }
        }
        .sheet(item: $preview) { item in
            ImportPreviewView(editor: editor, title: item.title, incoming: item.document) { result in
                message = result
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Clavimo configuration.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try editor.exportData().write(to: url, options: .atomic)
            message = String(localized: "Exported to \(url.lastPathComponent).")
        } catch {
            message = error.localizedDescription
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch editor.readDocument(at: url) {
        case let .success(document):
            preview = Preview(title: String(localized: "Import \(url.lastPathComponent)"), document: document)
        case let .failure(error):
            message = error.message
        }
    }
}

/// Rules pasted as text, for example from an AI assistant: first the text,
/// then the same preview of changes as a file import.
struct PasteRulesView: View {
    @Bindable var editor: ConfigEditor
    let completion: (String?) -> Void
    @State private var text = ""
    @State private var parsed: ConfigDocument?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let parsed {
            ImportPreviewView(editor: editor, title: String(localized: "Paste rules"), incoming: parsed, completion: completion)
        } else {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: String(localized: "Paste rules"),
                              subtitle: String(localized: "Paste the rules an AI assistant wrote, or any Clavimo rules in JSON. You see every change before it is applied."))
                TextEditor(text: $text)
                    .font(.system(.callout, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.s)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
                HStack {
                    Button(String(localized: "Paste from Clipboard")) {
                        text = NSPasteboard.general.string(forType: .string) ?? ""
                    }
                    Spacer()
                    Button(String(localized: "Cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(String(localized: "Continue")) { readText() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(Spacing.xl)
            .frame(width: 560, height: 480)
            .onAppear {
                // Start with the clipboard when it holds JSON.
                if let clip = NSPasteboard.general.string(forType: .string), PastedRules.extractJSON(from: clip) != nil {
                    text = clip
                }
            }
        }
    }

    private func readText() {
        guard let current = editor.document else { return }
        switch PastedRules.apply(text, to: current) {
        case let .success(document): parsed = document
        case let .failure(failure): errorMessage = failure.message
        }
    }
}

struct ImportPreviewView: View {
    @Bindable var editor: ConfigEditor
    let title: String
    let incoming: ConfigDocument
    let completion: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    private var diff: ConfigDiff { ConfigDiff(from: editor.document, to: incoming) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: title, subtitle: String(localized: "Review what changes. Your current configuration is kept as the previous version."))
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    if diff.isEmpty {
                        Text(String(localized: "Nothing changes.")).foregroundStyle(.secondary)
                    }
                    group(String(localized: "Added"), diff.added.map(\.name), symbol: "plus.circle.fill", color: .green)
                    group(String(localized: "Changed"), diff.changed.map(\.name), symbol: "pencil.circle.fill", color: .blue)
                    group(String(localized: "Removed"), diff.removed.map(\.name), symbol: "minus.circle.fill", color: .red)
                    group(String(localized: "New profiles"), diff.profilesAdded, symbol: "person.crop.circle.badge.plus", color: .green)
                    group(String(localized: "Removed profiles"), diff.profilesRemoved, symbol: "person.crop.circle.badge.minus", color: .red)
                    if let change = diff.activeProfileChange {
                        Label(String(localized: "Active profile: \(change.from) → \(change.to)"), systemImage: "arrow.left.arrow.right.circle.fill")
                    }
                    if !diff.unsupported.isEmpty {
                        WarningCard(symbol: "exclamationmark.triangle.fill", color: .orange,
                                    title: String(localized: "\(diff.unsupported.count) rules cannot run"),
                                    message: diff.unsupported.map(Messages.describe).joined(separator: "\n"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Apply")) {
                    if let error = editor.replace(with: incoming) {
                        errorMessage = error
                    } else {
                        completion(String(localized: "Configuration applied."))
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(diff.isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 520, height: 480)
    }

    @ViewBuilder
    private func group(_ title: String, _ names: [String], symbol: String, color: Color) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("\(title) (\(names.count))", systemImage: symbol).foregroundStyle(color).font(.headline)
                ForEach(names, id: \.self) { Text($0).padding(.leading, Spacing.xl) }
            }
        }
    }
}
