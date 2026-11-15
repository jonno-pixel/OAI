import CryptoKit
import Foundation

actor ModelRepository {
    let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func shard(_ name: String) -> (stem: String, index: Int)? {
        guard let range = name.range(
            of: "-(\\d{5})-of-\\d{5}\\.gguf$",
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        let suffix = name[range]
        return (String(name[..<range.lowerBound]), Int(suffix.dropFirst().prefix(5)) ?? 0)
    }

    private func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hasher = SHA256()
        while let chunk = try file.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func list() throws -> [ModelEntry] {
        guard let files = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [ModelEntry] = []
        for case let file as URL in files {
            guard file.pathExtension.lowercased() == "gguf",
                  try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }

            if let part = shard(file.lastPathComponent), part.index != 1 { continue }
            let relative = String(file.path.dropFirst(directory.path.count + 1))
            let bytes: Int64

            if let part = shard(file.lastPathComponent) {
                bytes = try FileManager.default.contentsOfDirectory(
                    at: file.deletingLastPathComponent(),
                    includingPropertiesForKeys: nil
                )
                .filter { shard($0.lastPathComponent)?.stem == part.stem }
                .reduce(Int64(0)) { total, sibling in
                    let size = try FileManager.default.attributesOfItem(atPath: sibling.path)[.size] as? NSNumber
                    return total + (size?.int64Value ?? 0)
                }
            } else {
                let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
                bytes = size?.int64Value ?? 0
            }

            entries.append(ModelEntry(
                path: relative,
                name: file.deletingPathExtension().lastPathComponent,
                bytes: bytes
            ))
        }
        return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func importFiles(_ sources: [URL]) throws -> [ModelEntry] {
        let access = sources.map { $0.startAccessingSecurityScopedResource() }
        defer {
            for (index, source) in sources.enumerated() where access[index] {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let group = UUID().uuidString
        let staging = directory.appendingPathComponent(".\(group).importing", isDirectory: true)
        let destination = directory.appendingPathComponent(group, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            var files: [URL] = []
            for source in sources {
                if try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                    if let enumerator = FileManager.default.enumerator(
                        at: source,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    ) {
                        for case let file as URL in enumerator
                        where file.pathExtension.lowercased() == "gguf" {
                            files.append(file)
                        }
                    }
                } else {
                    files.append(source)
                }
            }
            guard !files.isEmpty else { throw JJSFailure(message: "Geen GGUF-bestanden geselecteerd.") }

            var records: [(name: String, size: Int64, hash: String)] = []
            for source in files {
                let input = try FileHandle(forReadingFrom: source)
                let header: Data?
                do {
                    header = try input.read(upToCount: 4)
                    try input.close()
                } catch {
                    try? input.close()
                    throw error
                }
                guard header == Data("GGUF".utf8) else {
                    throw JJSFailure(message: "\(source.lastPathComponent) is geen GGUF-bestand.")
                }

                let name = source.pathExtension.lowercased() == "gguf"
                    ? source.lastPathComponent
                    : source.lastPathComponent + ".gguf"
                let target = staging.appendingPathComponent(name)
                guard !FileManager.default.fileExists(atPath: target.path) else {
                    throw JJSFailure(message: "Dubbele bestandsnaam: \(name). Importeer modelgroepen apart.")
                }

                let sourceHash = try digest(source)
                try FileManager.default.copyItem(at: source, to: target)
                guard try digest(target) == sourceHash else {
                    throw JJSFailure(message: "De kopie van \(name) wijkt af van het origineel.")
                }
                let size = try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber
                records.append((name, size?.int64Value ?? 0, sourceHash))
            }

            let manifest = records.map { ImportRecord(file: $0.name, bytes: $0.size, sha256: $0.hash) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: staging.appendingPathComponent("IMPORT.json"), options: .atomic)
            try FileManager.default.moveItem(at: staging, to: destination)
            return try list().filter { $0.path.hasPrefix(group + "/") }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    func download(
        _ urls: [URL],
        status: @escaping @Sendable (String) async -> Void
    ) async throws -> [ModelEntry] {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("JJS-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var files: [URL] = []
        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()
            await status("Download \(index + 1) / \(urls.count) · \(url.lastPathComponent)")
            let progress = GGUFDownloadProgress(prefix: "Download \(index + 1) / \(urls.count)", status: status)
            let (download, response) = try await URLSession.shared.download(from: url, delegate: progress)
            defer { try? FileManager.default.removeItem(at: download) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw JJSFailure(message: "Modeldownload mislukt (HTTP \(code)). Gebruik een rechtstreekse bestandslink, geen webpagina.")
            }
            try Task.checkCancellation()
            var name = (response.suggestedFilename ?? url.lastPathComponent) as NSString
            name = name.lastPathComponent as NSString
            if name.pathExtension.lowercased() != "gguf" {
                name = (name.deletingPathExtension + ".gguf") as NSString
            }
            let target = temporary.appendingPathComponent(name as String)
            guard !FileManager.default.fileExists(atPath: target.path) else {
                throw JJSFailure(message: "De downloadlinks leveren dezelfde bestandsnaam op. Download verschillende modellen apart.")
            }
            try FileManager.default.moveItem(at: download, to: target)
            files.append(target)
        }
        try Task.checkCancellation()
        await status("Download controleren en opslaan…")
        return try importFiles(files)
    }

    func exportURLs(for entry: ModelEntry) throws -> [URL] {
        let selected = try url(for: entry.path)
        guard let part = shard(selected.lastPathComponent) else { return [selected] }
        return try FileManager.default.contentsOfDirectory(
            at: selected.deletingLastPathComponent(), includingPropertiesForKeys: nil
        ).filter { shard($0.lastPathComponent)?.stem == part.stem }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func url(for path: String) throws -> URL {
        let root = directory.standardizedFileURL
        let candidate = directory.appendingPathComponent(path).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw JJSFailure(message: "Het modelpad ligt buiten de modellenmap.")
        }
        return candidate
    }

    func remove(_ entry: ModelEntry) throws {
        let selected = try url(for: entry.path)
        if let part = shard(selected.lastPathComponent) {
            let siblings = try FileManager.default.contentsOfDirectory(
                at: selected.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
            for file in siblings where shard(file.lastPathComponent)?.stem == part.stem {
                try FileManager.default.removeItem(at: file)
            }
        } else {
            try FileManager.default.removeItem(at: selected)
        }
    }
}

private struct ImportRecord: Codable {
    let file: String
    let bytes: Int64
    let sha256: String
}

private final class GGUFDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let prefix: String
    private let status: @Sendable (String) async -> Void
    private let lock = NSLock()
    private var lastUpdate = Date.distantPast

    init(prefix: String, status: @escaping @Sendable (String) async -> Void) {
        self.prefix = prefix
        self.status = status
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        lock.lock()
        let now = Date()
        let report = now.timeIntervalSince(lastUpdate) >= 0.5
        if report { lastUpdate = now }
        lock.unlock()
        guard report else { return }
        let received = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
        let expected = totalBytesExpectedToWrite > 0
            ? " / " + ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file)
            : ""
        let message = "\(prefix) · \(received)\(expected)"
        Task { await status(message) }
    }
}
