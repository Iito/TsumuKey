import CryptoKit
import SwiftUI

/// Downloads models listed in the Hugging Face repo's models.json into the
/// App Group folder (ModelStore), checking each file's SHA-256 first.
@MainActor
final class ModelDownloader: ObservableObject {
    @Published var available: [ModelStore.Model] = []
    @Published var progress: [String: Double] = [:]   // model id -> 0...1 while downloading
    @Published var error: String?
    @Published var revision = 0                       // bumps when files change on disk
    private var observations: [String: NSKeyValueObservation] = [:]

    private var build: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    func refresh() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: ModelStore.manifestURL)
            let manifest = try JSONDecoder().decode(ModelStore.Manifest.self, from: data)
            available = manifest.models.filter { $0.minBuild <= build }
            error = nil
        } catch {
            self.error = "Couldn't load the model list: \(error.localizedDescription)"
        }
    }

    func isInstalled(_ m: ModelStore.Model) -> Bool { _ = revision; return ModelStore.localURL(m.file) != nil }

    func download(_ m: ModelStore.Model) {
        guard progress[m.id] == nil, let dir = ModelStore.directory else {
            if ModelStore.directory == nil { error = "This build can't share files with the keyboard (no App Group)." }
            return
        }
        progress[m.id] = 0
        let task = URLSession.shared.downloadTask(with: m.url) { [weak self] tmp, _, err in
            // Verify and move here: the temporary file is gone once this returns.
            var result: String?
            if let tmp {
                if Self.sha256(tmp) == m.sha256 {
                    let dest = dir.appendingPathComponent(m.file)
                    try? FileManager.default.removeItem(at: dest)
                    do { try FileManager.default.moveItem(at: tmp, to: dest) } catch { result = error.localizedDescription }
                } else {
                    result = "\(m.name): checksum mismatch, file discarded"
                }
            } else {
                result = err?.localizedDescription ?? "download failed"
            }
            Task { @MainActor in
                guard let self else { return }
                self.progress[m.id] = nil
                self.observations[m.id] = nil
                self.error = result
                self.revision += 1
            }
        }
        observations[m.id] = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            Task { @MainActor in if self?.progress[m.id] != nil { self?.progress[m.id] = p.fractionCompleted } }
        }
        task.resume()
    }

    func delete(_ m: ModelStore.Model) {
        if let url = ModelStore.localURL(m.file) { try? FileManager.default.removeItem(at: url) }
        revision += 1
    }

    /// Streams the file so a 100 MB model isn't read into memory at once.
    nonisolated static func sha256(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct ModelsSection: View {
    @Binding var settings: KeyboardSettings
    @StateObject private var downloader = ModelDownloader()

    private var gemmaInstalled: Bool { _ = downloader.revision; return ModelStore.gemmaURL() != nil }
    private var smallLabel: String {
        _ = downloader.revision
        let info = ModelStore.rankerURL().flatMap { ModelStore.rankerInfo($0.url) }
        return "Small (\(info?.label ?? "4.5 MB"))"
    }

    var body: some View {
        Section {
            Picker("Correction model", selection: $settings.correctionModel) {
                Text(smallLabel).tag(CorrectionModel.dense)
                Text(gemmaInstalled ? "Gemma 3 (\(ModelStore.gemmaLabel))" : "Gemma 3 (not downloaded)").tag(CorrectionModel.gemma)
                if !CorrectionModel.choices.contains(settings.correctionModel) {
                    Text(settings.correctionModel.name).tag(settings.correctionModel)  // set by the bench
                }
            }
            ForEach(downloader.available) { m in
                HStack {
                    VStack(alignment: .leading) {
                        Text(m.name)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(m.size), countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let p = downloader.progress[m.id] {
                        ProgressView(value: p).frame(width: 80)
                    } else if downloader.isInstalled(m) {
                        Button("Delete", role: .destructive) { downloader.delete(m) }.buttonStyle(.borderless)
                    } else {
                        Button("Download") { downloader.download(m) }.buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text("Correction model")
        } footer: {
            if let e = downloader.error {
                Text(e).foregroundStyle(.red)
            } else if settings.correctionModel == .gemma && !gemmaInstalled {
                Text("Gemma isn't downloaded yet, so the keyboard keeps using the small model.")
            } else {
                Text("Models download from huggingface.co/iito-sama/tsumukey-models. The keyboard switches the next time it opens.")
            }
        }
        .task { await downloader.refresh() }
    }
}
