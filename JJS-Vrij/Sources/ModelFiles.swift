import Foundation
import CryptoKit

actor ModelFiles {
    private let root: URL
    init(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        var directory = self.root
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try directory.setResourceValues(attributes)
    }

    private func part(_ name: String) -> (family: String, number: Int)? {
        guard name.lowercased().hasSuffix(".gguf") else { return nil }
        let base = String(name.dropLast(5))
        guard let of = base.range(of: "-of-", options: .backwards),
              let separator = base[..<of.lowerBound].lastIndex(of: "-") else { return nil }
        let number = base[base.index(after: separator)..<of.lowerBound]
        let total = base[of.upperBound...]
        guard number.count == 5, total.count == 5,
              let index = Int(number), Int(total) != nil else { return nil }
        return (String(base[..<separator]), index)
    }

    func file(_ relative: String) throws -> URL {
        let candidate = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.pathComponents.count > root.pathComponents.count,
              candidate.pathComponents.starts(with: root.pathComponents) else {
            throw VrijError("Het geselecteerde modelpad ligt niet in de modellenopslag.")
        }
        return candidate
    }

    func all() throws -> [DiskModel] {
        guard let iterator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [DiskModel] = []
        for case let url as URL in iterator {
            guard url.pathExtension.lowercased() == "gguf",
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            if let shard = part(url.lastPathComponent), shard.number != 1 { continue }
            let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
            guard normalized.pathComponents.starts(with: root.pathComponents) else { continue }
            let path = normalized.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
            let members = try related(to: normalized)
            var size: Int64 = 0
            for member in members {
                size += (try FileManager.default.attributesOfItem(atPath: member.path)[.size] as? NSNumber)?.int64Value ?? 0
            }
            result.append(DiskModel(relativePath: path,
                                    title: url.deletingPathExtension().lastPathComponent, bytes: size))
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func related(to model: URL) throws -> [URL] {
        guard let shard = part(model.lastPathComponent) else { return [model] }
        return try FileManager.default.contentsOfDirectory(at: model.deletingLastPathComponent(),
            includingPropertiesForKeys: nil).filter {
                part($0.lastPathComponent)?.family == shard.family
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func export(_ model: DiskModel) throws -> [URL] { try related(to: file(model.relativePath)) }
    func delete(_ model: DiskModel) throws {
        for item in try export(model) { try FileManager.default.removeItem(at: item) }
    }

    private func hash(_ url: URL) throws -> SHA256.Digest {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var state = SHA256()
        while let bytes = try input.read(upToCount: 1_048_576), !bytes.isEmpty {
            try Task.checkCancellation()
            state.update(data: bytes)
        }
        return state.finalize()
    }

    func ingest(_ selections: [URL]) throws -> [DiskModel] {
        let granted = selections.map { $0.startAccessingSecurityScopedResource() }
        defer {
            for index in selections.indices where granted[index] {
                selections[index].stopAccessingSecurityScopedResource()
            }
        }
        let group = UUID().uuidString
        let staging = root.appendingPathComponent(".incoming-" + group, isDirectory: true)
        let final = root.appendingPathComponent(group, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: staging) } }
        var files: [URL] = []
        for selection in selections {
            if try selection.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                let iterator = FileManager.default.enumerator(at: selection,
                    includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let item = iterator?.nextObject() as? URL {
                    if item.pathExtension.lowercased() == "gguf",
                       try item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { files.append(item) }
                }
            } else { files.append(selection) }
        }
        guard !files.isEmpty else { throw VrijError("De selectie bevat geen GGUF-bestanden.") }
        for source in files {
            try Task.checkCancellation()
            let handle = try FileHandle(forReadingFrom: source)
            let magic: Data
            do { magic = try handle.read(upToCount: 4) ?? Data(); try handle.close() }
            catch { try? handle.close(); throw error }
            guard magic == Data([0x47,0x47,0x55,0x46]) else {
                throw VrijError("\(source.lastPathComponent) is geen GGUF-bestand. Een webpagina is geen modeldownload.")
            }
            let name = source.pathExtension.lowercased() == "gguf"
                ? source.lastPathComponent : source.lastPathComponent + ".gguf"
            let target = staging.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: target.path) else {
                throw VrijError("Dubbele bestandsnaam \(name). Importeer verschillende modelgroepen afzonderlijk.")
            }
            try FileManager.default.copyItem(at: source.resolvingSymlinksInPath(), to: target)
            guard try hash(source) == hash(target) else { throw VrijError("De modelkopie is niet identiek aan het bronbestand.") }
        }
        // Moving the entire staging directory makes partial imports invisible.
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: final)
        committed = true
        return try all().filter { $0.relativePath.hasPrefix(group + "/") }
    }

    func download(_ links: [URL], report: @escaping @Sendable (String) async -> Void) async throws -> [DiskModel] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Vrij-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var completed: [URL] = []
        for (index, link) in links.enumerated() {
            try Task.checkCancellation()
            guard ["http", "https"].contains(link.scheme?.lowercased() ?? ""), link.host != nil else {
                throw VrijError("Gebruik een geldige rechtstreekse http- of https-bestandslink.")
            }
            let label = "Modelbestand \(index + 1) / \(links.count)"
            await report(label + " downloaden…")
            let delegate = TransferProgress(label: label, report: report)
            let (temporary, response) = try await URLSession.shared.download(from: link, delegate: delegate)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw VrijError("De server leverde geen volledig modelbestand (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
            }
            var name = (response.suggestedFilename ?? link.lastPathComponent) as NSString
            name = name.lastPathComponent as NSString
            if name.pathExtension.lowercased() != "gguf" { name = (name as String + ".gguf") as NSString }
            let saved = folder.appendingPathComponent(name as String)
            guard !FileManager.default.fileExists(atPath: saved.path) else { throw VrijError("De links leveren dubbele bestandsnamen op.") }
            try FileManager.default.moveItem(at: temporary, to: saved)
            completed.append(saved)
        }
        try Task.checkCancellation()
        await report("GGUF-bestanden controleren en opslaan…")
        return try ingest(completed)
    }
}

private final class TransferProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let label: String
    private let report: @Sendable (String) async -> Void
    private let mutex = NSLock()
    private var reportedAt = Date.distantPast
    init(label: String, report: @escaping @Sendable (String) async -> Void) { self.label = label; self.report = report }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        mutex.lock()
        let now = Date()
        let update = now.timeIntervalSince(reportedAt) >= 0.4
        if update { reportedAt = now }
        mutex.unlock()
        guard update else { return }
        var message = label + " · " + ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
        if totalBytesExpectedToWrite > 0 {
            message += " / " + ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file)
        }
        let value = message
        Task { await report(value) }
    }
}
