import AVFoundation
import Foundation
import PDFKit
import Speech
import UniformTypeIdentifiers
import Vision

actor AttachmentReader {
    private var speechTasks: [UUID: SFSpeechRecognitionTask] = [:]
    private var speechContinuations: [UUID: CheckedContinuation<String, Error>] = [:]

    func read(_ url: URL) async throws -> String {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "pdf" {
            return try readPDF(url)
        }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           type.conforms(to: .image) {
            return try recognizeImage(url)
        }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           type.conforms(to: .audio) {
            return try await transcribeAudio(url)
        }
        return try readText(url)
    }

    private func readPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw JJSFailure(message: "De PDF kon niet worden geopend.")
        }
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
        let text = pages.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw JJSFailure(message: "Deze PDF bevat geen tekstlaag.")
        }
        return text
    }

    private func recognizeImage(_ url: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(url: url).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { throw JJSFailure(message: "Er is geen leesbare tekst in de afbeelding gevonden.") }
        return lines.joined(separator: "\n")
    }

    private func transcribeAudio(_ url: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw JJSFailure(message: "Lokale spraakherkenning is voor deze taal of dit toestel niet beschikbaar.")
        }
        try await requestSpeechAuthorization()

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        let taskID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                speechContinuations[taskID] = continuation
                speechTasks[taskID] = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    let text = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                    if text != nil || error != nil {
                        Task { await self?.finishSpeech(taskID, text: text, error: error) }
                    }
                }
            }
        } onCancel: {
            Task { await self.cancelSpeech(taskID) }
        }
    }

    private func finishSpeech(_ id: UUID, text: String?, error: Error?) {
        guard let continuation = speechContinuations.removeValue(forKey: id) else { return }
        speechTasks.removeValue(forKey: id)
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: text ?? "") }
    }

    private func cancelSpeech(_ id: UUID) {
        let task = speechTasks.removeValue(forKey: id)
        finishSpeech(id, text: nil, error: CancellationError())
        task?.cancel()
    }

    private func requestSpeechAuthorization() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return }
        guard status == .notDetermined else {
            throw JJSFailure(message: "Geef JJS toestemming voor lokale spraakherkenning in Instellingen.")
        }
        let result: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard result == .authorized else {
            throw JJSFailure(message: "Toestemming voor spraakherkenning is niet verleend.")
        }
    }

    private func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .utf16LittleEndian)
                ?? String(data: data, encoding: .utf16BigEndian) else {
            throw JJSFailure(message: "Dit bestand bevat geen leesbare UTF-8- of UTF-16-tekst.")
        }
        return text
    }
}
