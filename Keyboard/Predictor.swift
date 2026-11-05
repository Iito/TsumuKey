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
    /// Set on the main thread once the model is ready.
    private(set) var isReady = false

    func load() {
        queue.async { [self] in
            guard decoder == nil, !loadFailed else { return }
            let started = Date()
            guard let path = Bundle.main.path(forResource: Self.modelName, ofType: "gguf"),
                  let words = Bundle.main.url(forResource: "lexicon-enfrdees", withExtension: "bin"),
                  let lexicon = Lexicon(url: words),
                  let lm = LanguageModel(path: path) else {
                loadFailed = true
                TouchLog.log("LM load failed")
                return
            }
            decoder = WordDecoder(lm: lm, lexicon: lexicon)
            apply()
            TouchLog.log("LM loaded \(Int(Date().timeIntervalSince(started) * 1000))ms footprint=\(Memory.footprintMB())MB")
            DispatchQueue.main.async { self.isReady = true }
        }
    }

    /// Which languages predictions and corrections use (settings).
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
    }

    /// Gemma 3 270M with its vocabulary cut to English, French, German and
    /// Spanish (Tools/prune_vocab.py).
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
        TouchLog.log(result.log + " mem=\(Memory.footprintMB())MB")
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
