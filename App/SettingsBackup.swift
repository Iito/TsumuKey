import SwiftUI
import UniformTypeIdentifiers

/// All the app's settings in one JSON file, to keep them across a reinstall
/// or move them to another iPhone. Downloaded models aren't in it (they're
/// downloaded again), nor what the keyboard keeps on its own side (recent
/// emoji, words you undid a correction for): the app can't read those.
struct SettingsBackup: Codable {
    /// Lets a later version tell this file apart from other JSON.
    var format = "tsumukey-settings"
    var version = 1
    var app: String
    var exportedAt: Date
    var keyboard: KeyboardSettings
    var deleteTiming: DeleteTiming

    init(keyboard: KeyboardSettings, deleteTiming: DeleteTiming) {
        let info = Bundle.main.infoDictionary
        app = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        exportedAt = Date()
        self.keyboard = keyboard
        self.deleteTiming = deleteTiming
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// KeyboardSettings decodes field by field, so a file from an older or
    /// newer version keeps every setting both versions know.
    static func read(_ data: Data) throws -> SettingsBackup {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let backup = try d.decode(SettingsBackup.self, from: data)
        guard backup.format == "tsumukey-settings" else { throw BackupError.notSettings }
        return backup
    }

    enum BackupError: LocalizedError {
        case notSettings
        var errorDescription: String? { "This file isn't a TsumuKey settings file." }
    }
}

/// The file the save dialog writes ("TsumuKey Settings.json").
struct SettingsFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(_ backup: SettingsBackup) throws { data = try SettingsBackup.encoder.encode(backup) }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Advanced → Back Up: export to a file (Files, iCloud Drive, AirDrop…) or
/// import one, after a confirmation.
struct BackupSection: View {
    @Binding var settings: KeyboardSettings
    @Binding var timing: DeleteTiming
    @State private var importing = false
    @State private var exportFile: SettingsFile?
    @State private var pending: SettingsBackup?
    @State private var message: String?

    var body: some View {
        Section {
            Button {
                exportFile = try? SettingsFile(SettingsBackup(keyboard: settings, deleteTiming: timing))
            } label: {
                Label("Export settings", systemImage: "square.and.arrow.up")
            }
            // Its own view: two file dialogs on one view, and only the last one opens.
            .fileExporter(isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }),
                          document: exportFile, contentType: .json, defaultFilename: "TsumuKey Settings") { result in
                if case .failure(let error) = result { message = error.localizedDescription }
            }
            Button {
                importing = true
            } label: {
                Label("Import settings", systemImage: "square.and.arrow.down")
            }
        } header: {
            InfoHeader("Back Up", info: [
                "Export saves every setting in this app to a file in Files or iCloud Drive, to import after a reinstall or on another iPhone.",
                "Import replaces your settings with the file's.",
                "Not included: downloaded models (download them again), and what the keyboard remembers on its own (recent emoji, words you kept after undoing a correction).",
            ])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                pending = try SettingsBackup.read(Data(contentsOf: url))
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? "Couldn't read that file."
            }
        }
        .confirmationDialog("Replace your settings?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { backup in
            Button("Replace settings", role: .destructive) {
                settings = backup.keyboard
                timing = backup.deleteTiming
                message = "Settings imported."
            }
        } message: { backup in
            Text("From TsumuKey \(backup.app), exported \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened)).")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {}
    }
}
