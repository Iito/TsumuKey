import Foundation
import llama

/// The on-device English+French model (Gemma 3 270M with its vocabulary
/// pruned to the two languages). Not thread-safe: use it from one serial queue.
///
/// Sequence 0 in the KV cache holds the text before the current word and is
/// reused between calls, so each keystroke only pays for the new tokens.
/// Sequences 1...candidateSeqs score candidate words side by side, each
/// branching off the shared context.
final class LanguageModel: WordScorer {
    static let candidateSeqs = 10
    private static let batchCapacity = 32

    private let model: OpaquePointer
    private let ctx: OpaquePointer
    private let vocab: OpaquePointer?
    private let memory: llama_memory_t?
    private let nVocab: Int
    private let maxContextTokens = 96
    private var batch: llama_batch

    /// Text of each token, with SentencePiece's "▁" already turned into a space.
    private let pieces: [String]
    /// Tokens that can follow a finished word: a new word, punctuation, newline, end.
    private let boundaryTokens: [Int]
    /// Tokens that start a new word with letters (" the", " é…").
    private let wordStart: [Bool]
    /// Tokens that start with a letter and no space (first word of a text).
    private let letterStart: [Bool]
    /// Tokens that continue the current word ("ing", "'s").
    private let continuation: [Bool]

    private var contextTokens: [llama_token] = []
    /// Log-probabilities of the token right after the context.
    private var next: [Float] = []

    init?(path: String, threads: Int = 2) {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()

        var mp = llama_model_default_params()
        mp.n_gpu_layers = 0                 // CPU only: Metal's setup alone costs ~45 MB
        mp.load_mode = LLAMA_LOAD_MODE_MMAP // weights stay file-backed, paged in on demand
        mp.lazy_mode = LLAMA_LAZY_MODE_ON
        // Repacking copies the weights into memory iOS counts against us.
        mp.use_extra_bufts = false
        guard let m = llama_model_load_from_file(path, mp) else { return nil }

        var cp = llama_context_default_params()
        // Room for ~96 context tokens plus every candidate's few tokens. The
        // KV cache and the per-output logits buffer (batch x 48k vocab) are
        // the main costs on top of the weights, so both are kept small.
        cp.n_ctx = 256
        cp.n_batch = UInt32(Self.batchCapacity)
        cp.n_ubatch = UInt32(Self.batchCapacity)
        cp.n_seq_max = UInt32(Self.candidateSeqs + 1)
        cp.kv_unified = true   // candidates share the context's cache cells
        cp.n_threads = Int32(threads)
        cp.n_threads_batch = Int32(threads)
        guard let c = llama_init_from_model(m, cp) else {
            llama_model_free(m)
            return nil
        }
        model = m
        ctx = c
        vocab = llama_model_get_vocab(m)
        memory = llama_get_memory(c)
        nVocab = Int(llama_vocab_n_tokens(vocab))
        batch = llama_batch_init(Int32(Self.batchCapacity), 0, 1)

        var pieces: [String] = []
        pieces.reserveCapacity(nVocab)
        var buf = [CChar](repeating: 0, count: 64)
        for t in 0..<nVocab {
            let len = llama_token_to_piece(vocab, llama_token(t), &buf, 63, 0, false)
            pieces.append(len > 0
                ? String(decoding: buf[0..<Int(len)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
                : "")
        }
        self.pieces = pieces

        let eos = Int(llama_vocab_eos(vocab))
        var boundary: [Int] = []
        var wordStart = [Bool](repeating: false, count: nVocab)
        var letterStart = [Bool](repeating: false, count: nVocab)
        var continuation = [Bool](repeating: false, count: nVocab)
        for (t, p) in pieces.enumerated() {
            guard let first = p.first else {
                if t == eos { boundary.append(t) }
                continue
            }
            let isWordChar: (Character) -> Bool = { $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }
            if first == " " || first.isNewline || (first.isPunctuation && first != "'" && first != "’" && first != "-") {
                boundary.append(t)
            }
            let rest = p.dropFirst()
            if first == " ", let second = rest.first, second.isLetter, rest.allSatisfy(isWordChar) {
                wordStart[t] = true
            }
            if first.isLetter, p.allSatisfy(isWordChar) {
                letterStart[t] = true
                continuation[t] = true
            }
            if first == "'" || first == "’", p.allSatisfy(isWordChar) { continuation[t] = true }
        }
        boundaryTokens = boundary
        self.wordStart = wordStart
        self.letterStart = letterStart
        self.continuation = continuation
    }

    deinit {
        llama_batch_free(batch)
        llama_free(ctx)
        llama_model_free(model)
    }

    // MARK: Context

    /// Makes `text` the context for the next calls. Only tokens that differ
    /// from the previous context are computed.
    @discardableResult
    func setContext(_ text: String) -> Bool {
        var tokens = tokenize(text, bos: true)
        if tokens.count > maxContextTokens {
            // Keep the start-of-text token and the most recent words.
            tokens = [tokens[0]] + tokens.suffix(maxContextTokens - 1)
        }
        guard !tokens.isEmpty else { return false }

        var common = 0
        while common < min(tokens.count, contextTokens.count), tokens[common] == contextTokens[common] {
            common += 1
        }
        if common == tokens.count, common == contextTokens.count, !next.isEmpty { return true }
        // The last token always runs again: its output is the prediction we need.
        common = min(common, tokens.count - 1)

        clearCandidates()
        _ = llama_memory_seq_rm(memory, 0, Int32(common), -1)
        contextTokens = Array(tokens[..<common])
        next = []

        var items: [Item] = []
        for i in common..<tokens.count {
            items.append(Item(token: tokens[i], pos: Int32(i), seq: 0, output: i == tokens.count - 1))
        }
        var result: [Float] = []
        let ok = run(items) { _, logits in
            let norm = self.logNorm(logits)
            result = (0..<self.nVocab).map { logits[$0] - norm }
        }
        guard ok, !result.isEmpty else {
            llama_memory_clear(memory, true)
            contextTokens = []
            return false
        }
        contextTokens = tokens
        next = result
        return true
    }

    // MARK: Scoring

    /// Log-probability of each word coming next and then ending (followed by
    /// a space, punctuation or the end), given the current context.
    /// `leadingSpace`: the word follows a space ("I like| cats").
    func score(_ words: [String], leadingSpace: Bool) -> [Float] {
        var results = [Float](repeating: -.infinity, count: words.count)
        guard !next.isEmpty else { return results }
        let base = Int32(contextTokens.count)
        let prefix = leadingSpace ? " " : ""

        for start in stride(from: 0, to: words.count, by: Self.candidateSeqs) {
            clearCandidates()
            var items: [Item] = []
            var owners: [(word: Int, index: Int)] = []
            var tokensOf: [Int: [llama_token]] = [:]

            for (slot, w) in (start..<min(start + Self.candidateSeqs, words.count)).enumerated() {
                let tokens = tokenize(prefix + words[w], bos: false)
                guard !tokens.isEmpty, tokens.count <= 10 else { continue }
                tokensOf[w] = tokens
                results[w] = next[Int(tokens[0])]
                let seq = Int32(slot + 1)
                llama_memory_seq_cp(memory, 0, seq, -1, -1)
                for (k, token) in tokens.enumerated() {
                    items.append(Item(token: token, pos: base + Int32(k), seq: seq, output: true))
                    owners.append((w, k))
                }
            }
            _ = run(items) { i, logits in
                let (w, k) = owners[i]
                guard let tokens = tokensOf[w] else { return }
                let norm = self.logNorm(logits)
                if k + 1 < tokens.count {
                    results[w] += logits[Int(tokens[k + 1])] - norm
                } else {
                    results[w] += self.logSum(logits, self.boundaryTokens) - norm
                }
            }
        }
        return results
    }

    /// A quick, rough version of `score`: just the probability of each
    /// word's first token, which needs no extra model run. Used to pick
    /// which candidates deserve a full score.
    func quickScore(_ words: [String], leadingSpace: Bool) -> [Float] {
        guard !next.isEmpty else { return words.map { _ in 0 } }
        let prefix = leadingSpace ? " " : ""
        return words.map { w in
            guard let first = tokenize(prefix + w, bos: false).first else { return -.infinity }
            return next[Int(first)]
        }
    }

    /// The most likely next words, each extended a few tokens so whole
    /// words come out ("beaut"+"iful").
    func predict(count: Int = 3, leadingSpace: Bool) -> [String] {
        guard !next.isEmpty else { return [] }
        let starts = leadingSpace ? wordStart : letterStart
        var top: [(token: Int, logp: Float)] = []
        for t in 0..<nVocab where starts[t] {
            let lp = next[t]
            if top.count < count * 3 {
                top.append((t, lp))
                top.sort { $0.logp > $1.logp }
            } else if lp > top[top.count - 1].logp {
                top[top.count - 1] = (t, lp)
                top.sort { $0.logp > $1.logp }
            }
        }

        // Fold case-only duplicates (" The" / " the") before extending.
        var chosen: [Int] = []
        var seen = Set<String>()
        for (t, _) in top where seen.insert(pieces[t].lowercased()).inserted {
            chosen.append(t)
            if chosen.count == count { break }
        }

        clearCandidates()
        let base = Int32(contextTokens.count)
        var text = chosen.map { pieces[$0] }
        var last = chosen.map { llama_token($0) }
        var active = Array(repeating: true, count: chosen.count)
        for slot in chosen.indices { llama_memory_seq_cp(memory, 0, Int32(slot + 1), -1, -1) }

        for step in 0..<3 {
            let live = chosen.indices.filter { active[$0] }
            guard !live.isEmpty else { break }
            let items = live.map { Item(token: last[$0], pos: base + Int32(step), seq: Int32($0 + 1), output: true) }
            _ = run(items) { i, logits in
                let slot = live[i]
                var best = 0
                for t in 1..<self.nVocab where logits[t] > logits[best] { best = t }
                if self.continuation[best] {
                    text[slot] += self.pieces[best]
                    last[slot] = llama_token(best)
                } else {
                    active[slot] = false
                }
            }
        }
        return text.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: Plumbing

    private struct Item {
        var token: llama_token
        var pos: Int32
        var seq: Int32
        var output: Bool
    }

    private func clearCandidates() {
        for seq in 1...Self.candidateSeqs { _ = llama_memory_seq_rm(memory, Int32(seq), -1, -1) }
    }

    /// Decodes `items` in batch-sized chunks; `onOutput` gets the item index
    /// and its logits for every item that asked for output.
    private func run(_ items: [Item], onOutput: (Int, UnsafeMutablePointer<Float>) -> Void) -> Bool {
        var start = 0
        while start < items.count {
            let end = min(start + Self.batchCapacity, items.count)
            batch.n_tokens = 0
            var outputs: [(item: Int, row: Int32)] = []
            for k in start..<end {
                let item = items[k]
                let i = Int(batch.n_tokens)
                batch.token[i] = item.token
                batch.pos[i] = item.pos
                batch.n_seq_id[i] = 1
                batch.seq_id[i]![0] = item.seq
                batch.logits[i] = item.output ? 1 : 0
                if item.output { outputs.append((k, Int32(i))) }
                batch.n_tokens += 1
            }
            guard llama_decode(ctx, batch) == 0 else { return false }
            for (item, row) in outputs {
                if let logits = llama_get_logits_ith(ctx, row) { onOutput(item, logits) }
            }
            start = end
        }
        return true
    }

    private func tokenize(_ text: String, bos: Bool) -> [llama_token] {
        let capacity = text.utf8.count + 8
        var tokens = [llama_token](repeating: 0, count: capacity)
        let n = llama_tokenize(vocab, text, Int32(text.utf8.count), &tokens, Int32(capacity), bos, false)
        return n > 0 ? Array(tokens[0..<Int(n)]) : []
    }

    /// log(sum(exp(logits))) over the whole vocabulary.
    private func logNorm(_ logits: UnsafeMutablePointer<Float>) -> Float {
        var m = -Float.infinity
        for i in 0..<nVocab where logits[i] > m { m = logits[i] }
        var s: Float = 0
        for i in 0..<nVocab { s += expf(logits[i] - m) }
        return m + logf(s)
    }

    private func logSum(_ logits: UnsafeMutablePointer<Float>, _ tokens: [Int]) -> Float {
        var m = -Float.infinity
        for t in tokens where logits[t] > m { m = logits[t] }
        var s: Float = 0
        for t in tokens { s += expf(logits[t] - m) }
        return m + logf(s)
    }
}
