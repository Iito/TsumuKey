import Foundation
import os

/// Runs the language model off the main thread so typing never waits on it.
///
/// Two kinds of work share one serial queue:
/// - bar refreshes, where only the latest matters (older ones are skipped);
/// - corrections for a word just finished, which always run, in order,
///   because their result is applied to text already typed.
final class Predictor {
    /// One model per keyboard process. iOS can create a fresh keyboard
    /// controller while an old one lingers; each holding its own copy of the
    /// model nearly got the keyboard killed.
    static let shared = Predictor()
    private let queue = DispatchQueue(label: "tsumukey.lm", qos: .userInitiated)
    private var decoder: WordDecoder?          // queue only
    private var loadFailed = false             // queue only
    private var latestRefresh = 0              // guarded by `lock`
    private let lock = NSLock()
    private var languages: [PredictionLanguage] = [.english, .french]  // queue only
    private var model: CorrectionModel = .dense  // queue only
    /// Set on the main thread once the model is ready.
    private(set) var isReady = false

    func load() {
        queue.async { [self] in
            guard decoder == nil, !loadFailed else { return }
            guard let words = Bundle.main.url(forResource: "lexicon-enfrdees", withExtension: "bin"),
                  let lexicon = Lexicon(url: words),
                  let lm = makeScorer(lexicon) else {
                loadFailed = true
                return
            }
            decoder = WordDecoder(lm: lm, lexicon: lexicon)
            apply()
            DispatchQueue.main.async { self.isReady = true }
        }
    }

    /// Which languages predictions and corrections use (settings).
    /// Switches the correction model; the next `load` brings up the new one.
    func setModel(_ new: CorrectionModel) {
        queue.async { [self] in
            guard new != model else { return }
            model = new
            decoder = nil
            loadFailed = false
            DispatchQueue.main.async { self.isReady = false }
        }
    }

    private func makeScorer(_ lexicon: Lexicon) -> WordScorer? {  // queue only
        switch model {
        case .gemma:
            // Downloaded by the app (ModelStore); falls back to the small ranker
            // so the keyboard still corrects when Gemma isn't there.
            if let path = ModelStore.gemmaURL()?.path, let lm = LanguageModel(path: path) { return lm }
            guard let url = ModelStore.rankerURL()?.url, let r = Ranker(url: url) else { return nil }
            r.lexicon = lexicon
            return r
        case .dense, .moe:
            let bundledMoE = model == .moe ? Bundle.main.url(forResource: "ranker-moe", withExtension: "rank") : nil
            guard let url = bundledMoE ?? ModelStore.rankerURL()?.url,
                  let r = Ranker(url: url) else { return nil }
            r.lexicon = lexicon
            return r
        }
    }

    func setLanguages(_ new: [PredictionLanguage]) {
        queue.async { [self] in
            guard new != languages else { return }
            languages = new
            apply()
        }
    }

    private func apply() {  // queue only
        decoder?.lexicon.languages = languages.reduce(0) { $0 | $1.bit }
        decoder?.french = languages.contains(.french)
        (decoder?.lm as? Ranker)?.languages = languages
    }

    /// Gemma 3 270M, as published on the TsumuKey Hugging Face repo.
    static let modelName = "gemma-3-270m-enfrdees64k-Q4_0"

    /// Frees the model; the next `load` brings it back.
    func unload() {
        isReady = false
        queue.async { [self] in decoder = nil }
    }

    /// Quick bar update while a word is being typed.
    func refresh(_ request: DecodeRequest, completion: @escaping (DecodeResult) -> Void) {
        let id = lock.withLock { latestRefresh += 1; return latestRefresh }
        queue.async { [self] in
            // A newer refresh is already queued: this one would be stale.
            guard id == lock.withLock({ latestRefresh }) else { return }
            run(request, full: false, completion)
        }
    }

    /// Full check of a finished word.
    func correct(_ request: DecodeRequest, completion: @escaping (DecodeResult) -> Void) {
        queue.async { [self] in run(request, full: true, completion) }
    }

    private func run(_ request: DecodeRequest, full: Bool, _ completion: @escaping (DecodeResult) -> Void) {
        guard let decoder else { return }
        let result = decoder.decode(request, full: full)
        DispatchQueue.main.async { completion(result) }
    }
}

enum Memory {
    /// What iOS counts against the keyboard's memory limit.
    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    /// How much more iOS will allow before killing the keyboard.
    static func availableMB() -> Int { Int(os_proc_available_memory() / 1_048_576) }
}
