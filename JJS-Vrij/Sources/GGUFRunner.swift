import Foundation
import llama

// This actor owns every native pointer. No callback may use a released session.
actor GGUFRunner {
    private var network: OpaquePointer?
    private var execution: OpaquePointer?
    private var lexicon: OpaquePointer?
    private var work: llama_batch?
    private var identity = ""
    private let block: Int32 = 256

    init() { llama_backend_init() }
    deinit {
        if let work { llama_batch_free(work) }
        if let execution { llama_free(execution) }
        if let network { llama_model_free(network) }
        llama_backend_free()
    }

    private func reset() {
        if let work { llama_batch_free(work) }
        if let execution { llama_free(execution) }
        if let network { llama_model_free(network) }
        work = nil; execution = nil; network = nil; lexicon = nil; identity = ""
    }

    private func prepare(_ url: URL, _ settings: InferenceSettings) throws {
        let key = url.path + "|\(settings.context)|\(settings.metal)"
        if key == identity && execution != nil { return }
        reset()
        var parameters = llama_model_default_params()
        parameters.load_mode = LLAMA_LOAD_MODE_MMAP
        parameters.n_gpu_layers = settings.metal ? -1 : 0
        network = url.path.withCString { llama_model_load_from_file($0, parameters) }
        guard let network else { throw VrijError("De native bibliotheek kon dit GGUF-model niet laden. Controleer het bestand en het beschikbare geheugen.") }
        lexicon = llama_model_get_vocab(network)
        guard lexicon != nil else { reset(); throw VrijError("Het model heeft geen beschikbare tokenvocabulary.") }
        var configuration = llama_context_default_params()
        configuration.n_ctx = settings.context
        configuration.n_batch = UInt32(block)
        configuration.n_ubatch = UInt32(block)
        configuration.n_seq_max = 1
        configuration.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount))
        configuration.n_threads_batch = configuration.n_threads
        execution = llama_init_from_model(network, configuration)
        guard let execution, llama_n_ctx(execution) > 0 else {
            reset(); throw VrijError("Er kon geen uitvoerbare modelcontext worden aangemaakt.")
        }
        work = llama_batch_init(block, 0, 1)
        identity = key
    }

    private func prompt(_ messages: [RuntimeMessage], selected: String) throws -> String {
        guard let network else { throw VrijError("Er is geen model geladen.") }
        if selected.lowercased() == "raw" { return TextTransfer.rawPrompt(messages) }
        let embedded = llama_model_chat_template(network, nil)
        if selected.isEmpty && embedded == nil { return TextTransfer.rawPrompt(messages) }
        // A C-string chat formatter cannot represent NUL. Direct length-based
        // tokenization can, so preserve these messages through raw mode.
        if messages.contains(where: { $0.text.utf8.contains(0) || $0.role.utf8.contains(0) }) {
            return TextTransfer.rawPrompt(messages)
        }
        let allocated = messages.flatMap { [$0.role, $0.text] }.map { value in
            value.withCString { strdup($0) }
        }
        defer { for pointer in allocated { free(pointer) } }
        guard allocated.allSatisfy({ $0 != nil }) else { throw VrijError("De invoer kon niet in het geheugen worden geplaatst.") }
        let native = messages.indices.map {
            llama_chat_message(role: UnsafePointer(allocated[$0 * 2]!), content: UnsafePointer(allocated[$0 * 2 + 1]!))
        }
        func render(_ style: UnsafePointer<CChar>?) throws -> String {
            guard let style else { throw VrijError("Er is geen chattemplate beschikbaar; kies raw voor directe invoer.") }
            let needed = native.withUnsafeBufferPointer {
                llama_chat_apply_template(style, $0.baseAddress, $0.count, true, nil, 0)
            }
            guard needed > 0 else {
                throw VrijError("Deze chattemplate wordt niet door de meegeleverde bibliotheek verwerkt. Kies een andere template of raw voor directe invoer.")
            }
            var output = [CChar](repeating: 0, count: Int(needed) + 1)
            let length = native.withUnsafeBufferPointer { records in
                output.withUnsafeMutableBufferPointer {
                    llama_chat_apply_template(style, records.baseAddress, records.count, true, $0.baseAddress, needed)
                }
            }
            guard length >= 0 && length <= needed else { throw VrijError("Het toepassen van de modeltemplate is mislukt.") }
            return String(decoding: output.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        if selected.isEmpty { return try render(embedded) }
        return try selected.withCString { try render($0) }
    }

    private func tokens(_ text: String) throws -> [llama_token] {
        guard let lexicon, let byteCount = Int32(exactly: text.utf8.count) else {
            throw VrijError("Deze invoer kan niet in één aanroep van de native tokenizer worden verwerkt.")
        }
        let result = text.withCString { llama_tokenize(lexicon, $0, byteCount, nil, 0, true, true) }
        guard result != Int32.min else { throw VrijError("De tokenizer leverde een ongeldige grootte terug.") }
        let required = abs(result)
        guard required > 0 else { throw VrijError("De tokenizer leverde geen invoertokens terug.") }
        var buffer = [llama_token](repeating: 0, count: Int(required))
        let actual = text.withCString { input in
            buffer.withUnsafeMutableBufferPointer {
                llama_tokenize(lexicon, input, byteCount, $0.baseAddress, required, true, true)
            }
        }
        guard actual > 0 && actual <= required else { throw VrijError("De invoer kon niet worden getokeniseerd.") }
        buffer.removeLast(buffer.count - Int(actual))
        return buffer
    }

    private func piece(_ token: llama_token) throws -> [UInt8] {
        guard let lexicon else { throw VrijError("Tokenvocabulary ontbreekt.") }
        var bytes = [CChar](repeating: 0, count: 64)
        var count = bytes.withUnsafeMutableBufferPointer {
            llama_token_to_piece(lexicon, token, $0.baseAddress, Int32($0.count), 0, false)
        }
        if count < 0 {
            guard count != Int32.min else { throw VrijError("Ongeldige tokengrootte.") }
            bytes = [CChar](repeating: 0, count: Int(-count))
            count = bytes.withUnsafeMutableBufferPointer {
                llama_token_to_piece(lexicon, token, $0.baseAddress, Int32($0.count), 0, false)
            }
        }
        guard count >= 0 && count <= bytes.count else { throw VrijError("Het token kon niet als tekst worden gelezen.") }
        return bytes.prefix(Int(count)).map { UInt8(bitPattern: $0) }
    }

    private func calculate(_ input: ArraySlice<llama_token>, position: Int, finalLogits: Bool) throws {
        guard let execution, var work else { throw VrijError("De uitvoercontext ontbreekt.") }
        guard input.count <= Int(block), input.count <= Int(llama_n_batch(execution)) else {
            throw VrijError("De verwerkingsbuffer past niet in de native batch.")
        }
        work.n_tokens = Int32(input.count)
        for (offset, token) in input.enumerated() {
            work.token[offset] = token
            work.pos[offset] = Int32(position + offset)
            work.n_seq_id[offset] = 1
            work.seq_id[offset]![0] = 0
            work.logits[offset] = finalLogits && offset == input.count - 1 ? 1 : 0
        }
        let code = llama_decode(execution, work)
        guard code == 0 else { throw VrijError("De native berekening is onderbroken (code \(code)). Ontvangen tekst wordt bewaard.") }
    }

    func reply(to messages: [RuntimeMessage], modelFile: URL, settings: InferenceSettings,
               receive: @Sendable (RuntimeEvent) async throws -> Void) async throws -> RuntimeSummary {
        try Task.checkCancellation()
        try await receive(.progress("Model in het geheugen laden…"))
        try prepare(modelFile, settings)
        guard let execution, let lexicon, let memory = llama_get_memory(execution) else {
            throw VrijError("De bibliotheek kon geen geheugencontext voor tekstgeneratie leveren.")
        }
        let input = try tokens(prompt(messages, selected: settings.template))
        let capacity = Int(llama_n_ctx(execution))
        llama_memory_clear(memory, true)
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw VrijError("De tokenkeuze kon niet worden geïnitialiseerd.")
        }
        defer { llama_sampler_free(sampler) }
        if settings.temperature == 0 { llama_sampler_chain_add(sampler, llama_sampler_init_greedy()) }
        else {
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(settings.temperature))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: UInt32.min...UInt32.max)))
        }
        var active: [llama_token] = []
        var shifts: UInt64 = 0
        func room(_ incoming: Int) throws {
            if active.count + incoming <= capacity { return }
            let retained = Array(active.suffix(min(capacity / 2, capacity - incoming)))
            llama_memory_clear(memory, true)
            var start = 0
            while start < retained.count {
                try Task.checkCancellation()
                let end = min(start + Int(block), retained.count)
                try calculate(retained[start..<end], position: start, finalLogits: false)
                start = end
            }
            active = retained
            shifts &+= 1
        }
        var consumed = 0
        while consumed < input.count {
            try Task.checkCancellation()
            let count = min(Int(block), max(1, capacity / 2), input.count - consumed)
            try room(count)
            let end = consumed + count
            try calculate(input[consumed..<end], position: active.count, finalLogits: true)
            active.append(contentsOf: input[consumed..<end]); consumed = end
            try await receive(.progress("Invoer verwerken · \(consumed.formatted()) / \(input.count.formatted()) tokens"))
        }
        try await receive(.progress("Antwoord schrijven…"))
        var decoder = TokenTextBuffer()
        var text = ""
        var count: UInt64 = 0
        var reportedAt = Date()
        do {
            // There is deliberately no output-token budget, generation timer,
            // content filter or application-injected stop sequence here.
            while true {
                try Task.checkCancellation()
                let next = llama_sampler_sample(sampler, execution, -1)
                if llama_vocab_is_eog(lexicon, next) { break }
                text += decoder.receive(try piece(next))
                try room(1)
                try calculate([next][...], position: active.count, finalLogits: true)
                active.append(next); count &+= 1
                if Date().timeIntervalSince(reportedAt) >= 0.15 && !text.isEmpty {
                    try await receive(.output(text)); text = ""; reportedAt = Date()
                }
                if count.isMultiple(of: 32) { await Task.yield() }
            }
        } catch {
            text += decoder.finish()
            if !text.isEmpty { try await receive(.output(text)) }
            throw error
        }
        text += decoder.finish()
        if !text.isEmpty { try await receive(.output(text)) }
        return RuntimeSummary(produced: count, shifts: shifts)
    }
}
