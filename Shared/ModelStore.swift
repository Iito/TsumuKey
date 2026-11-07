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

    /// Ranker the keyboard uses: the newest downloaded round (ranker-rN.rank),
    /// else the one built into the app.
    static func rankerURL() -> (url: URL, round: Int?)? {
        if let dir = directory,
           let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            let rounds = files.compactMap { f -> (Int, String)? in
                guard f.hasPrefix("ranker-r"), f.hasSuffix(".rank"),
                      let n = Int(f.dropFirst(8).dropLast(5)) else { return nil }
                return (n, f)
            }
            if let best = rounds.max(by: { $0.0 < $1.0 }) {
                return (dir.appendingPathComponent(best.1), best.0)
            }
        }
        return Bundle.main.url(forResource: "ranker-dense", withExtension: "rank").map { ($0, bundledRankerRound) }
    }

    /// Training round of Models/ranker-dense.rank (update with the file).
    static let bundledRankerRound = 7

    /// Gemma is download-only (not bundled: it would add 100 MB to the app).
    static let gemmaFile = "gemma-3-270m-enfrdees64k-Q4_0.gguf"
    static func gemmaURL() -> URL? { localURL(gemmaFile) }
}
