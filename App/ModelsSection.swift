import CryptoKit
import Network
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
    @Published var checked = false                    // list fetched at least once this session

    private let session = URLSession(configuration: .default)
    private let monitor = NWPathMonitor()
    private var tasks: [String: URLSessionDownloadTask] = [:]

    init() { monitor.start(queue: DispatchQueue(label: "net")) }

    deinit { monitor.cancel() }

    /// Not on Wi-Fi (or Ethernet) right now: downloads ask first.
    var onMobileData: Bool {
        let p = monitor.currentPath
        return p.status == .satisfied && !p.usesInterfaceType(.wifi) && !p.usesInterfaceType(.wiredEthernet)
    }

    func cancel(_ m: ModelStore.Model) { tasks[m.id]?.cancel() }

    private static func describe(_ error: Error) -> String {
        let e = error as NSError
        if e.domain == NSURLErrorDomain, e.code == NSURLErrorDataNotAllowed {
            return "Mobile data is off for TsumuKey (Settings → TsumuKey → Mobile Data). Use Wi-Fi or turn it on."
        }
        if e.domain == NSURLErrorDomain, [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost].contains(e.code) {
            return "No connection. Try again on Wi-Fi."
        }
        return e.localizedDescription
    }

    private var build: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    func refresh() async {
        do {
            let (data, _) = try await session.data(from: ModelStore.manifestURL)
            let manifest = try JSONDecoder().decode(ModelStore.Manifest.self, from: data)
            available = manifest.models.filter { $0.minBuild <= build }
            error = nil
        } catch {
            self.error = "Couldn't load the model list. " + Self.describe(error)
        }
        checked = true
    }

    func isInstalled(_ m: ModelStore.Model) -> Bool { _ = revision; return ModelStore.localURL(m.file) != nil }

    /// The version in use when `m` is a newer small model: a downloaded older
    /// round, or the built-in one. nil when `m` is not an update.
    func replaces(_ m: ModelStore.Model) -> Int? {
        _ = revision
        guard let r = m.round, let current = ModelStore.rankerURL()?.round, current < r else { return nil }
        return current
    }

    func download(_ m: ModelStore.Model) {
        guard progress[m.id] == nil, let dir = ModelStore.directory else {
            if ModelStore.directory == nil { error = "This build can't share files with the keyboard (no App Group)." }
            return
        }
        progress[m.id] = 0
        let task = session.downloadTask(with: m.url) { [weak self] tmp, _, err in
            // Verify and move here: the temporary file is gone once this returns.
            var result: String?
            if let tmp {
                if Self.sha256(tmp) == m.sha256 {
                    let dest = dir.appendingPathComponent(m.file)
                    try? FileManager.default.removeItem(at: dest)
                    do {
                        try FileManager.default.moveItem(at: tmp, to: dest)
                        // A new small model replaces older downloaded rounds.
                        if let r = m.round {
                            for old in ModelStore.downloadedRankers() where old.round < r {
                                try? FileManager.default.removeItem(at: old.url)
                            }
                        }
                    } catch { result = error.localizedDescription }
                } else {
                    result = "\(m.name): checksum mismatch, file discarded"
                }
            } else if (err as? URLError)?.code == .cancelled {
                result = nil  // cancelled by the user; nothing was kept
            } else {
                result = err.map(Self.describe) ?? "download failed"
            }
            Task { @MainActor in
                guard let self else { return }
                self.progress[m.id] = nil
                self.observations[m.id] = nil
                self.tasks[m.id] = nil
                self.error = result
                self.revision += 1
            }
        }
        observations[m.id] = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            Task { @MainActor in if self?.progress[m.id] != nil { self?.progress[m.id] = p.fractionCompleted } }
        }
        tasks[m.id] = task
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
    @State private var confirmCellular: ModelStore.Model?

    /// Downloads right away on Wi-Fi; on mobile data, asks first.
    private func request(_ m: ModelStore.Model) {
        if downloader.onMobileData { confirmCellular = m } else { downloader.download(m) }
    }

    private var gemmaInstalled: Bool { _ = downloader.revision; return ModelStore.gemmaURL() != nil }
    private var smallLabel: String {
        _ = downloader.revision
        let current = ModelStore.rankerURL()
        let info = current.flatMap { ModelStore.rankerInfo($0.url) }
        let version = current?.round.map { " v\($0)" } ?? ""
        return "Small\(version) (\(info?.label ?? "4.5 MB"))"
    }

    var body: some View {
        Section {
            NavigationLink {
                OrderedListPage(title: "Prediction Languages",
                                items: $settings.predictionLanguages, all: PredictionLanguage.allCases,
                                name: \.name,
                                limit: settings.autoLanguages ? PredictionLanguage.allCases.count : KeyboardSettings.maxPredictionLanguages,
                                firstNote: nil, topAction: "Move to Top",
                                info: [settings.autoLanguages
                                       ? "Detect Language is on: autocorrect knows the words of every language listed, and the two your recent words are in lead. The top two are where it starts."
                                       : "Up to \(KeyboardSettings.maxPredictionLanguages). Suggestions and autocorrect mix them; more would make autocorrect swap right words for look-alikes in another language."])
            } label: {
                LabeledContent("Prediction Languages",
                               value: (settings.autoLanguages ? settings.predictionLanguages : settings.manualLanguages)
                                   .map(\.name).joined(separator: ", "))
            }
            Toggle("Detect Language", isOn: $settings.autoLanguages)
            Picker("Model", selection: $settings.correctionModel) {
                Text(smallLabel).tag(CorrectionModel.dense)
                Text(gemmaInstalled ? "Gemma 3 (\(ModelStore.gemmaLabel))" : "Gemma 3 (not downloaded)").tag(CorrectionModel.gemma)
                if !CorrectionModel.choices.contains(settings.correctionModel) {
                    Text(settings.correctionModel.name).tag(settings.correctionModel)  // set by the bench
                }
            }
            Button(downloader.checked ? "Check again" : "Check for models") {
                Task { await downloader.refresh() }
            }
            .alert("Download on mobile data?", isPresented: Binding(get: { confirmCellular != nil },
                                                                    set: { if !$0 { confirmCellular = nil } }),
                   presenting: confirmCellular) { m in
                Button("Download") { downloader.download(m) }
                Button("Cancel", role: .cancel) {}
            } message: { m in
                Text("You're not on Wi-Fi. \(m.name) is \(ByteCountFormatter.string(fromByteCount: Int64(m.size), countStyle: .file)).")
            }
            ForEach(downloader.available) { m in
                HStack {
                    VStack(alignment: .leading) {
                        Text(m.name)
                        Group {
                            if let current = downloader.replaces(m) {
                                Text("Update from v\(current) · " + ByteCountFormatter.string(fromByteCount: Int64(m.size), countStyle: .file))
                            } else {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(m.size), countStyle: .file))
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let p = downloader.progress[m.id] {
                        ProgressView(value: p).frame(width: 80)
                        Button {
                            downloader.cancel(m)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Cancel download")
                    } else if downloader.isInstalled(m) {
                        Button("Delete", role: .destructive) { downloader.delete(m) }.buttonStyle(.borderless)
                    } else if downloader.replaces(m) != nil {
                        Button("Update") { request(m) }.buttonStyle(.borderless)
                    } else {
                        Button("Download") { request(m) }.buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            InfoHeader("Prediction Model", info: [
                "The model corrects typos and suggests the next word, in your prediction languages (up to \(KeyboardSettings.maxPredictionLanguages)).",
                "Small is built in. Gemma 3 is larger and optional: download it here.",
                "The app goes online only when you tap Check or Download, to fetch models from huggingface.co/iito-sama/tsumukey-models. On mobile data it asks before downloading.",
                "The keyboard never connects, and nothing you type leaves your phone. A new model is used the next time the keyboard opens.",
            ])
        } footer: {
            // Only what needs attention; the explanation is behind ⓘ.
            if let e = downloader.error {
                Text(e).foregroundStyle(.red)
            } else if settings.correctionModel == .gemma && !gemmaInstalled {
                Text("Gemma isn't downloaded yet, so the keyboard keeps using the small model.")
            }
        }
    }
}
