import Foundation

@main
enum ModelRepositoryTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("JJS-ModelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ModelRepository(directory: root.appendingPathComponent("Models"))
        let input = root.appendingPathComponent("Input")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        // Fixtures exercise transfer, not model inference.
        let bytes = Data("GGUF".utf8) + Data(repeating: 42, count: 8192)
        for name in ["sample-00001-of-00002.gguf", "sample-00002-of-00002.gguf"] {
            try bytes.write(to: input.appendingPathComponent(name))
        }
        let imported = try await repository.importFiles([input])
        precondition(imported.count == 1 && imported[0].bytes == Int64(bytes.count * 2), "Imported: \(imported)")
        let exported = try await repository.exportURLs(for: imported[0])
        precondition(exported.count == 2)
        for file in exported { let exportedBytes = try Data(contentsOf: file); precondition(exportedBytes == bytes) }
        try await repository.remove(imported[0])
        let empty = try await repository.list()
        precondition(empty.isEmpty)

        // A GGUF header is accepted even if its source has a different extension.
        let alternate = input.appendingPathComponent("model.bin")
        try bytes.write(to: alternate)
        let renamed = try await repository.importFiles([alternate])
        precondition(renamed.count == 1 && renamed[0].name == "model.bin")
        try await repository.remove(renamed[0])

        let base = URL(string: ProcessInfo.processInfo.environment["JJS_TEST_SERVER"]!)!
        let downloaded = try await repository.download([base.appendingPathComponent("model.gguf")]) { _ in }
        precondition(downloaded.count == 1)
        let files = try await repository.exportURLs(for: downloaded[0])
        let downloadedBytes = try Data(contentsOf: files[0]); precondition(downloadedBytes == bytes)
        for name in ["bad.gguf", "missing.gguf"] {
            do {
                _ = try await repository.download([base.appendingPathComponent(name)]) { _ in }
                fatalError("Invalid download unexpectedly accepted: \(name)")
            } catch is JJSFailure {}
        }
        let remaining = try await repository.list()
        precondition(remaining.count == 1, "Failed downloads must not leave models behind")
        do {
            _ = try await repository.url(for: "../../outside.gguf")
            fatalError("Path traversal accepted")
        } catch is JJSFailure {}
        print("JJS model import/export/download tests passed.")
    }
}
