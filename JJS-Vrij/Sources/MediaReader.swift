import Foundation
import UIKit
import PDFKit
import Vision
import Speech
import UniformTypeIdentifiers

actor MediaReader {
    private struct Listening {
        let result: CheckedContinuation<String, Error>
        var task: SFSpeechRecognitionTask?
    }
    private var listening: [UUID: Listening] = [:]

    func text(from url: URL) async throws -> String {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let kind = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        if url.pathExtension.lowercased() == "pdf" { return try pdf(url) }
        if kind?.conforms(to: .image) == true { return try image(url) }
        if kind?.conforms(to: .audio) == true { return try await audio(url) }
        return try TextTransfer.decode(Data(contentsOf: url))
    }

    private func image(_ url: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(url: url).perform([request])
        let output = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        guard !output.isEmpty else { throw VrijError("Er is geen leesbare tekst in de afbeelding gevonden.") }
        return output
    }

    private func pdf(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw VrijError("Het PDF-bestand kon niet worden geopend.") }
        var result: [String] = []
        for number in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: number) else { continue }
            if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(text)
            } else if let bitmap = page.thumbnail(of: CGSize(width: 1800, height: 2400), for: .mediaBox).cgImage {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(cgImage: bitmap).perform([request])
                result.append((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
            }
        }
        let output = result.joined(separator: "\n\n")
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VrijError("Deze PDF bevat geen leesbare tekst.") }
        return output
    }

    private func audio(_ url: URL) async throws -> String {
        var permission = SFSpeechRecognizer.authorizationStatus()
        if permission == .notDetermined {
            permission = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        guard permission == .authorized else { throw VrijError("Geef in iOS-instellingen toestemming voor spraakherkenning.") }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw VrijError("Lokale spraakherkenning is op dit toestel voor de gekozen taal niet beschikbaar.")
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                listening[id] = Listening(result: continuation, task: nil)
                listening[id]?.task = recognizer.recognitionTask(with: request) { [weak self] response, error in
                    let text = response?.isFinal == true ? response?.bestTranscription.formattedString : nil
                    if error != nil || text != nil {
                        Task { await self?.complete(id, text: text, error: error) }
                    }
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func complete(_ id: UUID, text: String?, error: Error?) {
        guard let pending = listening.removeValue(forKey: id) else { return }
        if let error { pending.result.resume(throwing: error) }
        else { pending.result.resume(returning: text ?? "") }
    }
    private func cancel(_ id: UUID) {
        guard let pending = listening.removeValue(forKey: id) else { return }
        pending.result.resume(throwing: CancellationError())
        pending.task?.cancel()
    }
}
