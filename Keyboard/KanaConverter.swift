import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// Kana → kanji conversion with azooKey's open-source engine
/// (AzooKeyKanaKanjiConverter, MIT). Runs on its own serial queue; only the
/// newest request is answered, so fast typing never queues up stale work.
final class KanaConverter {
    static let shared = KanaConverter()

    private let queue = DispatchQueue(label: "kana-converter", qos: .userInitiated)
    private var converter: KanaKanjiConverter?
    private let lock = NSLock()
    private var latest = 0

    private lazy var options: ConvertRequestOptions = {
        // Learning (words picked often rise to the top) lives in the
        // keyboard's own container.
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return ConvertRequestOptions(
            N_best: 10,
            requireJapanesePrediction: true,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            learningType: .inputAndOutput,
            memoryDirectoryURL: documents,
            sharedContainerURL: documents,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: nil,
            metadata: .init(versionString: "TsumuKey")
        )
    }()

    func load() {
        queue.async {
            guard self.converter == nil else { return }
            self.converter = KanaKanjiConverter.withDefaultDictionary()
        }
    }

    /// Saves what was learned and frees the dictionary.
    func unload() {
        queue.async {
            guard let converter = self.converter else { return }
            converter.commitUpdateLearningData()
            self.converter = nil
        }
    }

    /// Candidates for the reading, best first. `done` runs on the main
    /// queue, and only for the newest request.
    /// `predict: false` with `fresh: true` is for one-off words (the ABC
    /// keyboard's Japanese chip): exact conversions only, no leftover state
    /// from the previous request.
    func candidates(for text: ComposingText, predict: Bool = true, fresh: Bool = false,
                    done: @escaping ([Candidate]) -> Void) {
        lock.lock(); latest += 1; let id = latest; lock.unlock()
        queue.async {
            guard self.isLatest(id) else { return }
            if self.converter == nil { self.converter = KanaKanjiConverter.withDefaultDictionary() }
            if fresh { self.converter!.stopComposition() }
            var options = self.options
            options.requireJapanesePrediction = predict
            let result = self.converter!.requestCandidates(text, options: options)
            DispatchQueue.main.async {
                if self.isLatest(id) { done(result.mainResults) }
            }
        }
    }

    /// The user chose `candidate`: remember it for next time.
    func didCommit(_ candidate: Candidate) {
        queue.async {
            self.converter?.setCompletedData(candidate)
            self.converter?.updateLearningData(candidate)
        }
    }

    /// Composition ended (committed or abandoned).
    func reset() {
        lock.lock(); latest += 1; lock.unlock()
        queue.async { self.converter?.stopComposition() }
    }

    func save() {
        queue.async { self.converter?.commitUpdateLearningData() }
    }

    private func isLatest(_ id: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return id == latest
    }
}
