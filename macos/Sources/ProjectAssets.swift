import Foundation
import CryptoKit

enum ProjectJSON {
    static func embedded(_ text:String) -> Any? {
        guard let first = text.first(where:{!$0.isWhitespace}), first == "{" || first == "[",
              let data = text.data(using:.utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with:data)
    }
    static func string(_ value:Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]) else { return nil }
        return String(data:data,encoding:.utf8)
    }
}

/// A portable copy owns its media. The original draft and original media are
/// never edited; importing only rebases paths within the copied project.
struct ProjectAssets {
    private let fm = FileManager.default

    private func documents(in folder: URL) throws -> [(URL, Any)] {
        var output: [(URL, Any)] = []
        guard let files = fm.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { throw CocoaError(.fileReadUnknown) }
        for case let file as URL in files {
            if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { files.skipDescendants(); continue }
            guard file.pathExtension.lowercased() == "json" else { continue }
            let data = try Data(contentsOf: file)
            guard data.count < 32_000_000, let value = try? JSONSerialization.jsonObject(with: data) else {
                // Opaque auxiliary configuration is copied byte-for-byte. Main
                // drafts cannot be declared portable if their links are unreadable.
                if ["draft_info.json", "draft_content.json", "template.json", "mini_draft.json"].contains(file.lastPathComponent) {
                    throw LauncherError.message("Не удалось прочитать связи материалов проекта. Экспортируйте его в режиме «Только проект».")
                }
                continue
            }
            output.append((file, value))
        }
        return output
    }
    private func localPath(_ text: String) -> String? {
        if text.hasPrefix("/") { return URL(fileURLWithPath: text).standardizedFileURL.path }
        if let url = URL(string: text), url.isFileURL { return url.standardizedFileURL.path }
        return nil
    }
    private func references(_ value: Any, scope: Bool = false, key: String = "") -> [String] {
        if let dict = value as? [String: Any] {
            return dict.flatMap { name, child in
                references(child, scope: scope || ["materials", "draft_materials", "mini_draft_data"].contains(name), key: name)
            }
        }
        if let array = value as? [Any] { return array.flatMap { references($0, scope: scope, key: key) } }
        let normalized = key.replacingOccurrences(of: "_", with: "").lowercased()
        if let text = value as? String {
            if scope, (normalized.hasSuffix("path") || normalized.hasSuffix("pathlist")), let path = localPath(text) { return [path] }
            if let inner = ProjectJSON.embedded(text) { return references(inner,scope:scope) }
        }
        return []
    }
    private func contains(_ parent: String, _ child: String) -> Bool { child == parent || child.hasPrefix(parent + "/") }
    private func fileHash(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func fingerprint(_ url: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        func walk(_ item: URL, _ name: String) throws {
            let info = try item.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            guard info.isSymbolicLink != true else { throw LauncherError.message("Материал содержит символическую ссылку: \(item.lastPathComponent). Полная копия не создана.") }
            if info.isDirectory == true {
                result[name] = "directory"
                for child in try fm.contentsOfDirectory(atPath: item.path) { try walk(item.appendingPathComponent(child), name + "/" + child) }
            } else if info.isRegularFile == true { result[name] = try fileHash(item) }
            else { throw CocoaError(.fileReadUnsupportedScheme) }
        }
        try walk(url, "")
        return result
    }
    private func replace(_ value: Any, mapping: [(String, String)]) -> Any {
        if let text = value as? String, let path = localPath(text),
           let pair = mapping.first(where: { contains($0.0, path) }) {
            let result = pair.1 + path.dropFirst(pair.0.count)
            return text.hasPrefix("file:") ? URL(fileURLWithPath: result).absoluteString : result
        }
        if let text = value as? String, let inner = ProjectJSON.embedded(text) {
            let updated = replace(inner,mapping:mapping)
            if !NSDictionary(dictionary:["v":inner]).isEqual(to:["v":updated]) { return ProjectJSON.string(updated) ?? text }
        }
        if let array = value as? [Any] { return array.map { replace($0, mapping: mapping) } }
        if let dict = value as? [String: Any] { return dict.mapValues { replace($0, mapping: mapping) } }
        return value
    }
    func validatePortable(in copy: URL) throws {
        guard fm.fileExists(atPath:copy.appendingPathComponent("capcut-launcher-media.json").path) else { return }
        let docs = try documents(in:copy)
        let stored = (docs.first { $0.0.lastPathComponent == "draft_meta_info.json" }?.1 as? [String:Any])?["draft_fold_path"] as? String
        for path in Set(docs.flatMap { references($0.1) }) {
            guard let prefix = [copy.path,stored].compactMap({$0}).first(where:{contains($0,path)}) else {
                throw LauncherError.message("Копия с материалами повреждена: обнаружены внешние ссылки. Повторите экспорт.")
            }
            let file = copy.appendingPathComponent(String(path.dropFirst(prefix.count)).trimmingCharacters(in:CharacterSet(charactersIn:"/")))
            guard file.standardizedFileURL.path.hasPrefix(copy.standardizedFileURL.path+"/"),
                  file.resolvingSymlinksInPath().path == file.standardizedFileURL.path,
                  fm.fileExists(atPath:file.path) else {
                throw LauncherError.message("В копии отсутствует материал: \(file.lastPathComponent). Повторите экспорт.")
            }
        }
    }
    /// Includes effect/font resource directories as well as video/audio/images.
    /// All destinations are inside this project, so single-project import works.
    func collect(in copy: URL, original: URL) throws {
        if let files = fm.enumerator(at:copy,includingPropertiesForKeys:[.isSymbolicLinkKey]) {
            for case let file as URL in files where try file.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink == true {
                throw LauncherError.message("Проект содержит символические ссылки. Для полной копии замените их файлами или выберите «Только проект».")
            }
        }
        let docs = try documents(in: copy)
        let originalPath = original.standardizedFileURL.path
        let stored = (docs.first { $0.0.lastPathComponent == "draft_meta_info.json" }?.1 as? [String: Any])?["draft_fold_path"] as? String
        let paths = Set(docs.flatMap { references($0.1) })
        var external: [String] = [], missing: [String] = []
        for path in paths.sorted() {
            // Internal files already travel with the project. Verify that each
            // referenced internal file is present in the copy as well.
            let internalRoot = [originalPath, stored].compactMap { $0 }.first { contains($0, path) }
            let source = internalRoot.map { copy.path + path.dropFirst($0.count) } ?? path
            if !fm.fileExists(atPath: source) { missing.append(URL(fileURLWithPath: path).lastPathComponent) }
            else if internalRoot == nil { external.append(path) }
        }
        guard missing.isEmpty else {
            throw LauncherError.message("Не найдены материалы: \(missing.count).\n\(missing.prefix(8).joined(separator: "\n"))\nВосстановите исходники или выберите «Только проект».")
        }
        // Keep only outer resource folders when both a folder and its child are
        // referenced. Identical basenames from different locations stay distinct.
        var sources: [String] = []
        for path in external.sorted(by: { $0.count < $1.count }) {
            if !sources.contains(where: { contains($0, path) }) { sources.append(path) }
        }
        let assets = copy.appendingPathComponent("Resources/LauncherMedia-" + UUID().uuidString)
        if !sources.isEmpty { try fm.createDirectory(at: assets, withIntermediateDirectories: true) }
        var mapping: [(String, String)] = []
        for (index, path) in sources.enumerated() {
            let source = URL(fileURLWithPath: path)
            var directory: ObjCBool = false
            _ = fm.fileExists(atPath: path, isDirectory: &directory)
            // Never recursively gather a broad user/library directory from a
            // malformed material reference or a directory containing the export.
            if directory.boolValue && (source.pathComponents.count < 5 || contains(path, copy.path) || contains(path, originalPath) || source == fm.homeDirectoryForCurrentUser || source.deletingLastPathComponent() == fm.homeDirectoryForCurrentUser) {
                throw LauncherError.message("Недопустимая папка материала: \(source.lastPathComponent). Выберите «Только проект».")
            }
            let target = assets.appendingPathComponent(String(index)).appendingPathComponent(source.lastPathComponent)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let before = try fingerprint(source)
            try fm.copyItem(at: source, to: target)
            guard try fingerprint(target) == before, try fingerprint(source) == before else {
                throw LauncherError.message("Материал изменился во время копирования. Повторите экспорт при закрытом CapCut.")
            }
            mapping.append((path, target.path))
        }
        // Resource configurations may themselves contain absolute references.
        // Rebase these too, but never collect new external files during import.
        for (file, object) in try documents(in: copy) {
            let updated = replace(object, mapping: mapping.sorted { $0.0.count > $1.0.count })
            if !NSDictionary(dictionary: ["v": object]).isEqual(to: ["v": updated]) {
                try JSONSerialization.data(withJSONObject: updated, options: [.sortedKeys, .prettyPrinted]).write(to: file, options: .atomic)
            }
        }
        try JSONSerialization.data(withJSONObject:["format":"capcut-launcher-media","version":1]).write(to:copy.appendingPathComponent("capcut-launcher-media.json"),options:.atomic)
    }
}
