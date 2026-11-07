import Foundation

/// Models downloaded on demand from the Hugging Face repo, kept in the App
/// Group folder so the keyboard can read what the app downloaded. The app
/// downloads (the keyboard only reads): extensions have little memory and
/// no network without Full Access.
enum ModelStore {
    static let repo = URL(string: "https://huggingface.co/iito-sama/tsumukey-models/resolve/main/")!
    static var manifestURL: URL { repo.appendingPathComponent("models.json") }

    struct Manifest: Codable { let format: Int; let models: [Model] }
    struct Model: Codable, Identifiable, Hashable {
        let id: String
        let kind: String     // "ranker" (.rank) or "gguf"
        let name: String
        let file: String
        let size: Int
        let sha256: String
        let minBuild: Int
        let notes: String?
        var url: URL { ModelStore.repo.appendingPathComponent(file) }
        /// Training round of a small model (ranker-rN.rank), its version number.
        var round: Int? { ModelStore.rankerRound(file) }
    }

    static func rankerRound(_ file: String) -> Int? {
        guard file.hasPrefix("ranker-r"), file.hasSuffix(".rank") else { return nil }
        return Int(file.dropFirst(8).dropLast(5))
    }

    /// Downloaded small models, by round.
    static func downloadedRankers() -> [(round: Int, url: URL)] {
        guard let dir = directory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files.compactMap { f in rankerRound(f).map { ($0, dir.appendingPathComponent(f)) } }
    }

    /// App Group folder; nil when the build has no App Group entitlement.
    static var directory: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedSettings.appGroup)
        else { return nil }
        let dir = base.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func localURL(_ file: String) -> URL? {
        guard let url = directory?.appendingPathComponent(file),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Ranker the keyboard uses: the newest round, downloaded (ranker-rN.rank)
    /// or built into the app. An old download must not hide a newer bundled one.
    static func rankerURL() -> (url: URL, round: Int?)? {
        var downloaded: (URL, Int)?
        if let best = downloadedRankers().max(by: { $0.round < $1.round }) {
            downloaded = (best.url, best.round)
        }
        if let d = downloaded, d.1 > bundledRankerRound { return d }
        // The keyboard finds it in its own bundle, the app inside the plug-in.
        let bundled = Bundle.main.url(forResource: "ranker-dense", withExtension: "rank")
            ?? Bundle.main.builtInPlugInsURL?.appendingPathComponent("Keyboard.appex/ranker-dense.rank")
        return bundled.map { ($0, bundledRankerRound) } ?? downloaded
    }

    /// Shape of a .rank file, read from its header (export.py, TKR3).
    struct RankerInfo {
        let layers, heads, dim, experts, params: Int
        /// "Transformer 2L × 4H, 4.3M params" (plus experts for a MoE head).
        var label: String {
            let moe = experts > 0 ? ", MoE \(experts) experts" : ""
            return "Transformer \(layers)L × \(heads)H\(moe), \(String(format: "%.1f", Double(params) / 1e6))M params"
        }
    }

    /// Attention heads per layer: fixed by train.py's Block(d, 4) and Ranker.swift.
    static let rankerHeads = 4

    static func rankerInfo(_ url: URL) -> RankerInfo? {
        guard let h = try? FileHandle(forReadingFrom: url),
              let data = try? h.read(upToCount: 48), data.count == 48, data.prefix(4) == Data("TKR3".utf8)
        else { return nil }
        try? h.close()
        let v = (0..<11).map { i in Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4 + i * 4, as: UInt32.self) }) }
        let (buckets, d, layers, hidden, experts, ctx) = (v[0], v[1], v[2], v[3], v[4], v[5])
        let shared = v[8] == 1, eh = v[9], nf = v[10]
        // Same tensors as train.py's Ranker (and the export order).
        let perLayer = 2 * d + (3 * d * d + 3 * d) + (d * d + d) + 2 * d + (2 * d * d + 2 * d) + (2 * d * d + d)
        let nin = 3 * d + nf, n = max(experts, 1)
        var params = buckets * d + ctx * d + (4 * d + d) + layers * perLayer + 2 * d + (d * d + d)
        params += n * (nin * eh + eh + eh + 1)
        if experts > 0 { params += experts * d + experts }
        if shared { params += nin * hidden + hidden + hidden + 1 }
        return RankerInfo(layers: layers, heads: rankerHeads, dim: d, experts: experts, params: params)
    }

    /// Training round of Models/ranker-dense.rank (update with the file).
    static let bundledRankerRound = 9

    /// Gemma is download-only (not bundled: it would add 100 MB to the app).
    static let gemmaFile = "gemma-3-270m-enfrdees64k-Q4_0.gguf"
    static func gemmaURL() -> URL? { localURL(gemmaFile) }
    /// From the GGUF: 18 blocks, 4 heads (1 KV), vocabulary pruned to 64k.
    static let gemmaLabel = "Transformer 18L × 4H, 141M params"
}
