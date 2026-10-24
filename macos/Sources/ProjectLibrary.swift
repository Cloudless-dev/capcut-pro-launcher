import Foundation
import CryptoKit
import ImageIO

struct CapCutProject: Identifiable, Equatable {
    var id: String { folder.lastPathComponent }
    let folder: URL
    let draftID: String
    let name: String
    let modified: Date
    let byteCount: Int64
    let cover: Data?
    let incomplete: Bool
}
struct TrashedCapCutProject: Identifiable, Equatable {
    let id: String
    let project: CapCutProject
    let deleted: Date
    let originalFolderName: String
}
struct ProjectOperationResult {
    var completed = 0
    var skipped = 0
    var destination: URL?
    var sourceFingerprints:[String:[String:String]] = [:]
}

/// Only recognized, direct child project folders are managed. All mutations
/// require CapCut to be closed; user media outside these folders is untouched.
struct ProjectLibrary {
    let root: URL
    let backups: URL
    var isCapCutRunning: () -> Bool = NativeAccountStore.isCapCutRunning
    var trashItem: (URL)throws->URL = { url in
        var result:NSURL?
        try FileManager.default.trashItem(at:url,resultingItemURL:&result)
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return result as URL
    }
    var moveProject: (URL,URL)throws->Void = { try FileManager.default.moveItem(at:$0,to:$1) }
    var trashURL: URL { root.appendingPathComponent(".launcher-trash",isDirectory:true) }
    private var fm: FileManager { .default }
    private var indexURL: URL { root.appendingPathComponent("root_meta_info.json") }
    private func json(_ url: URL) -> [String:Any]? {
        guard !isLink(url), let data = try? Data(contentsOf:url), data.count < 32_000_000 else { return nil }
        return try? JSONSerialization.jsonObject(with:data) as? [String:Any]
    }
    private func isLink(_ url: URL) -> Bool { (try? url.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) == true }
    private func child(_ folder: URL) -> Bool {
        folder.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path && !isLink(folder)
    }
    private func guardClosed() throws {
        if isCapCutRunning() { throw LauncherError.message("Сначала полностью закройте CapCut для работы с файлами проектов.") }
    }
    private func safeIndex() throws -> (Data?,[String:Any]) {
        guard fm.fileExists(atPath:indexURL.path) else { return (nil,["all_draft_store":[],"draft_ids":0,"root_path":root.path]) }
        guard !isLink(indexURL), let data = try? Data(contentsOf:indexURL),
              let value = try? JSONSerialization.jsonObject(with:data) as? [String:Any], value["all_draft_store"] is [[String:Any]] else {
            throw LauncherError.message("Индекс проектов повреждён или имеет неизвестный формат. Файлы не изменены.")
        }
        return (data,value)
    }
    private func unchangedIndex(_ original: Data?) throws {
        let now = try? Data(contentsOf:indexURL)
        if now != original { throw LauncherError.message("Список проектов изменился. Обновите его и повторите действие.") }
    }
    private func saveJSON(_ value: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.prettyPrinted]).write(to:url,options:.atomic)
    }
    private func backupIndex(_ data: Data?) throws {
        guard let data else { return }
        let folder = backups.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let file = folder.appendingPathComponent("root_meta_info.json")
        try data.write(to:file,options:.atomic); try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
    func scan() throws -> [CapCutProject] {
        guard fm.fileExists(atPath:root.path) else { return [] }
        let indexed = (json(indexURL)?["all_draft_store"] as? [[String:Any]] ?? [])
        return try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey,.contentModificationDateKey],options:[.skipsHiddenFiles]).compactMap { folder in
            guard child(folder), (try? folder.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true else { return nil }
            let meta = json(folder.appendingPathComponent("draft_meta_info.json"))
            let entry = indexed.first { ($0["draft_fold_path"] as? String).map { URL(fileURLWithPath:$0).lastPathComponent == folder.lastPathComponent } == true }
            let hasDraft = ["draft_info.json","draft_content.json"].contains { fm.fileExists(atPath:folder.appendingPathComponent($0).path) }
            guard meta != nil || hasDraft || entry != nil else { return nil }
            let info = meta ?? entry ?? [:]
            let title = (info["draft_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? folder.lastPathComponent
            let timestamp = (info["tm_draft_modified"] as? NSNumber)?.doubleValue
            let date = timestamp.map { Date(timeIntervalSince1970:$0 > 1e14 ? $0 / 1e6 : $0 > 1e11 ? $0 / 1e3 : $0) }
                ?? (try? folder.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let coverName = info["draft_cover"] as? String ?? "draft_cover.jpg"
            let coverURL = folder.appendingPathComponent(coverName).standardizedFileURL
            let cover = coverURL.path.hasPrefix(folder.standardizedFileURL.path+"/") ? thumbnail(coverURL) : nil
            return CapCutProject(folder:folder,draftID:info["draft_id"] as? String ?? "",name:title,modified:date,byteCount:folderBytes(folder),cover:cover,incomplete:!hasDraft || meta == nil)
        }.sorted { $0.modified > $1.modified }
    }
    private func thumbnail(_ url: URL) -> Data? {
        guard !isLink(url), url.resolvingSymlinksInPath().path == url.standardizedFileURL.path,
              let size = try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize, size < 20_000_000,
              let source = CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:320,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil) else { return nil }
        CGImageDestinationAddImage(output,image,nil)
        return CGImageDestinationFinalize(output) ? data as Data : nil
    }
    private func folderBytes(_ folder: URL) -> Int64 {
        guard let e = fm.enumerator(at:folder,includingPropertiesForKeys:[.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey]) else { return 0 }
        var total:Int64 = 0
        for case let file as URL in e {
            if isLink(file) { e.skipDescendants(); continue }
            if let v = try? file.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey]), v.isRegularFile == true { total += Int64(v.fileSize ?? 0) }
        }
        return total
    }
    private func validated(_ projects: [CapCutProject]) throws {
        guard !projects.isEmpty, Set(projects.map(\.id)).count == projects.count else { throw LauncherError.message("Выберите проекты.") }
        for project in projects {
            guard child(project.folder), fm.fileExists(atPath:project.folder.path),
                  (json(project.folder.appendingPathComponent("draft_meta_info.json"))?["draft_id"] as? String ?? project.draftID) == project.draftID else {
                throw LauncherError.message("Список проектов изменился. Обновите его и повторите действие.")
            }
        }
    }
    /// Hashes both copies before changing any path references. Symlinks remain
    /// links, never a way to read, copy or delete files outside the project.
    private func manifest(_ folder: URL) throws -> [String:String] {
        var result:[String:String] = [:]
        func walk(_ directory: URL, prefix: String) throws {
            for name in try fm.contentsOfDirectory(atPath:directory.path) {
                let file = directory.appendingPathComponent(name), relative = prefix+name
                if isLink(file) { result[relative] = "link:" + (try fm.destinationOfSymbolicLink(atPath:file.path)); continue }
                let values = try file.resourceValues(forKeys:[.isRegularFileKey,.isDirectoryKey])
                if values.isDirectory == true { result[relative] = "directory"; try walk(file,prefix:relative+"/"); continue }
                guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
                let handle = try FileHandle(forReadingFrom:file); defer { try? handle.close() }
                var hash = SHA256()
                while let bytes = try handle.read(upToCount:1_048_576), !bytes.isEmpty { hash.update(data:bytes) }
                result[relative] = hash.finalize().map { String(format:"%02x",$0) }.joined()
            }
        }
        try walk(folder,prefix:"")
        return result
    }
    private func rebased(_ value: Any, from old: String, to new: String) -> Any {
        if let text = value as? String {
            if text == old || text.hasPrefix(old+"/") { return new + text.dropFirst(old.count) }
            if let url = URL(string:text), url.isFileURL {
                let path = url.standardizedFileURL.path
                if path == old || path.hasPrefix(old+"/") { return URL(fileURLWithPath:new+path.dropFirst(old.count)).absoluteString }
            }
            if let inner = ProjectJSON.embedded(text) {
                let updated = rebased(inner,from:old,to:new)
                if !NSDictionary(dictionary:["v":inner]).isEqual(to:["v":updated]) { return ProjectJSON.string(updated) ?? text }
            }
            return text
        }
        if let list = value as? [Any] { return list.map { rebased($0,from:old,to:new) } }
        if let dict = value as? [String:Any] { return dict.mapValues { rebased($0,from:old,to:new) } }
        return value
    }
    private func rewriteCopy(_ copied: URL, original: URL, final: URL, library: URL) throws {
        let storedPath = json(copied.appendingPathComponent("draft_meta_info.json"))?["draft_fold_path"] as? String
        guard let e = fm.enumerator(at:copied,includingPropertiesForKeys:[.isSymbolicLinkKey]) else { throw CocoaError(.fileReadUnknown) }
        for case let file as URL in e {
            if isLink(file) { e.skipDescendants(); continue }
            guard file.pathExtension == "json", let data = try? Data(contentsOf:file), data.count < 32_000_000,
                  let object = try? JSONSerialization.jsonObject(with:data), object is [String:Any] || object is [Any] else { continue }
            var updated = rebased(object,from:copied.path,to:final.path)
            updated = rebased(updated,from:original.path,to:final.path)
            if let storedPath, storedPath != original.path { updated = rebased(updated,from:storedPath,to:final.path) }
            if file.lastPathComponent == "draft_meta_info.json", var meta = updated as? [String:Any] {
                meta["draft_fold_path"] = final.path; meta["draft_root_path"] = library.path; updated = meta
            }
            if !NSDictionary(dictionary:["v":object]).isEqual(to:["v":updated]) { try saveJSON(updated,to:file) }
        }
    }
    private func indexRecord(_ project: CapCutProject, metadata:[String:Any], copied:URL, final:URL, library:URL) -> [String:Any] {
        let sourceIndex = json(project.folder.deletingLastPathComponent().appendingPathComponent("root_meta_info.json"))?["all_draft_store"] as? [[String:Any]] ?? []
        var record = sourceIndex.first { !project.draftID.isEmpty && $0["draft_id"] as? String == project.draftID } ?? metadata
        record = rebased(record,from:project.folder.path,to:final.path) as? [String:Any] ?? record
        if let old = record["draft_fold_path"] as? String, old != final.path {
            record = rebased(record,from:old,to:final.path) as? [String:Any] ?? record
        }
        record["draft_fold_path"] = final.path; record["draft_root_path"] = library.path
        record["draft_id"] = project.draftID; record["draft_name"] = project.name
        let content = fm.fileExists(atPath:copied.appendingPathComponent("draft_info.json").path) ? "draft_info.json" : "draft_content.json"
        record["draft_json_file"] = final.appendingPathComponent(content).path
        if record["draft_timeline_materials_size"] == nil { record["draft_timeline_materials_size"] = metadata["draft_timeline_materials_size_"] ?? 0 }
        if record["streaming_edit_draft_ready"] == nil { record["streaming_edit_draft_ready"] = true }
        return record
    }
    @discardableResult private func copyVerified(_ source: URL, to target: URL) throws -> [String:String] {
        let before = try manifest(source)
        try fm.copyItem(at:source,to:target)
        guard try manifest(target) == before, try manifest(source) == before else {
            throw LauncherError.message("Не удалось проверить копию проекта. Исходные файлы сохранены.")
        }
        return before
    }
    func export(_ projects: [CapCutProject], to parent: URL, includeMedia: Bool = false) throws -> ProjectOperationResult {
        try guardClosed(); try validated(projects)
        let destinationParent = parent.resolvingSymlinksInPath().standardizedFileURL
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard destinationParent.path != canonicalRoot.path, !destinationParent.path.hasPrefix(canonicalRoot.path+"/") else {
            throw LauncherError.message("Выберите папку вне текущей библиотеки проектов.")
        }
        let name = "CapCut Projects " + ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-") + " " + UUID().uuidString.prefix(6)
        let final = destinationParent.appendingPathComponent(name)
        let stage = destinationParent.appendingPathComponent(".capcut-export-"+UUID().uuidString)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false)
        var committed = false
        defer { if !committed { try? fm.removeItem(at:stage) } }
        var entries:[[String:Any]] = []
        var fingerprints:[String:[String:String]] = [:]
        for project in projects {
            let copy = stage.appendingPathComponent(project.id), target = final.appendingPathComponent(project.id)
            fingerprints[project.id] = try copyVerified(project.folder,to:copy)
            if includeMedia { try ProjectAssets().collect(in:copy,original:project.folder) }
            try rewriteCopy(copy,original:project.folder,final:target,library:final)
            if let meta = json(copy.appendingPathComponent("draft_meta_info.json")) { entries.append(indexRecord(project,metadata:meta,copied:copy,final:target,library:final)) }
        }
        try saveJSON(["all_draft_store":entries,"draft_ids":entries.count,"root_path":final.path],to:stage.appendingPathComponent("root_meta_info.json"))
        try saveJSON(["format":"capcut-launcher-projects","version":2,"includes_media":includeMedia,"projects":projects.map(\.id)],to:stage.appendingPathComponent("capcut-launcher-projects.json"))
        try fm.moveItem(at:stage,to:final); committed = true
        return ProjectOperationResult(completed:projects.count,destination:final,sourceFingerprints:fingerprints)
    }
    private func checkedTrashRoot(create:Bool = false) throws -> URL {
        // Never follow a link placed at the storage boundary.
        guard !isLink(trashURL), trashURL.resolvingSymlinksInPath().standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent(".launcher-trash").path else {
            throw LauncherError.message("Не удалось безопасно открыть корзину лаунчера.")
        }
        if create { try fm.createDirectory(at:trashURL,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]) }
        return trashURL
    }
    func scanTrash() throws -> [TrashedCapCutProject] {
        let bin = try checkedTrashRoot()
        guard fm.fileExists(atPath:bin.path) else { return [] }
        return try fm.contentsOfDirectory(at:bin,includingPropertiesForKeys:[.isDirectoryKey]).compactMap { entry in
            guard UUID(uuidString:entry.lastPathComponent) != nil, !isLink(entry),
                  let receipt = json(entry.appendingPathComponent("receipt.json")), receipt["version"] as? Int == 1,
                  let name = receipt["folder_name"] as? String, !name.isEmpty, !name.hasPrefix("."), !name.contains("/"),
                  let id = receipt["draft_id"] as? String else { return nil }
            let folder = entry.appendingPathComponent(name,isDirectory:true)
            guard !isLink(folder), (try? folder.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true else { return nil }
            let metadata = json(folder.appendingPathComponent("draft_meta_info.json"))
            let cover = folder.appendingPathComponent(metadata?["draft_cover"] as? String ?? "draft_cover.jpg").standardizedFileURL
            let project = CapCutProject(folder:folder,draftID:id,name:receipt["name"] as? String ?? name,
                modified:Date(timeIntervalSince1970:receipt["modified"] as? Double ?? 0),byteCount:folderBytes(folder),
                cover:cover.path.hasPrefix(folder.standardizedFileURL.path+"/") ? thumbnail(cover) : nil,
                incomplete:receipt["incomplete"] as? Bool ?? false)
            return TrashedCapCutProject(id:entry.lastPathComponent,project:project,deleted:Date(timeIntervalSince1970:receipt["deleted"] as? Double ?? 0),originalFolderName:name)
        }.sorted { $0.deleted > $1.deleted }
    }
    private func checkedTrashItems(_ items:[TrashedCapCutProject]) throws -> [TrashedCapCutProject] {
        guard !items.isEmpty, Set(items.map(\.id)).count == items.count else { throw LauncherError.message("Выберите проекты.") }
        let current = Dictionary(uniqueKeysWithValues:try scanTrash().map { ($0.id,$0) })
        return try items.map { item in
            guard let stored = current[item.id], stored.project.draftID == item.project.draftID,
                  stored.project.folder.standardizedFileURL.path == item.project.folder.standardizedFileURL.path else {
                throw LauncherError.message("Список проектов изменился. Обновите его и повторите действие.")
            }
            return stored
        }
    }
    func trash(_ projects: [CapCutProject]) throws -> ProjectOperationResult {
        try guardClosed(); try validated(projects)
        let (original,index) = try safeIndex(); try backupIndex(original)
        let bin = try checkedTrashRoot(create:true)
        var prepared:[(original:URL,payload:URL,entry:URL)] = []
        do {
            for project in projects {
                try guardClosed()
                let entry = bin.appendingPathComponent(UUID().uuidString,isDirectory:true)
                let payload = entry.appendingPathComponent(project.id,isDirectory:true)
                try fm.createDirectory(at:entry,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
                prepared.append((project.folder,payload,entry))
                let record = (index["all_draft_store"] as? [[String:Any]] ?? []).first {
                    (!$0.isEmpty && !project.draftID.isEmpty && $0["draft_id"] as? String == project.draftID)
                    || ($0["draft_fold_path"] as? String == project.folder.path)
                } ?? json(project.folder.appendingPathComponent("draft_meta_info.json")) ?? [:]
                try saveJSON(["version":1,"folder_name":project.id,"draft_id":project.draftID,"name":project.name,
                              "deleted":Date().timeIntervalSince1970,"modified":project.modified.timeIntervalSince1970,
                              "incomplete":project.incomplete,"original_path":project.folder.path as String,"index_record":record],to:entry.appendingPathComponent("receipt.json"))
                try moveProject(project.folder,payload)
            }
            try guardClosed(); try unchangedIndex(original)
            var updated = index
            let ids = Set(projects.map(\.draftID).filter { !$0.isEmpty }), folders = Set(projects.map(\.id))
            updated["all_draft_store"] = (index["all_draft_store"] as? [[String:Any]] ?? []).filter { entry in
                if let id = entry["draft_id"] as? String, ids.contains(id) { return false }
                if let path = entry["draft_fold_path"] as? String {
                    let url = URL(fileURLWithPath:path).standardizedFileURL
                    if url.deletingLastPathComponent().resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path && folders.contains(url.lastPathComponent) { return false }
                }
                return true
            }
            try saveJSON(updated,to:indexURL)
        } catch {
            for item in prepared.reversed() {
                if fm.fileExists(atPath:item.payload.path), !fm.fileExists(atPath:item.original.path) { try? fm.moveItem(at:item.payload,to:item.original) }
                if !fm.fileExists(atPath:item.payload.path) { try? fm.removeItem(at:item.entry) }
            }
            throw error
        }
        return ProjectOperationResult(completed:projects.count)
    }
    func restore(_ requested:[TrashedCapCutProject]) throws -> ProjectOperationResult {
        try guardClosed()
        let items = try checkedTrashItems(requested).sorted { $0.deleted > $1.deleted }
        let (original,index) = try safeIndex(); try backupIndex(original)
        var ids = Set(try scan().map(\.draftID).filter { !$0.isEmpty })
        var entries = index["all_draft_store"] as? [[String:Any]] ?? []
        let stage = root.appendingPathComponent(".capcut-restore-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false)
        defer { try? fm.removeItem(at:stage) }
        var added:[URL] = [], restored:[TrashedCapCutProject] = []
        var result = ProjectOperationResult()
        do {
            for item in items {
                try guardClosed()
                if !item.project.draftID.isEmpty && ids.contains(item.project.draftID) { result.skipped += 1; continue }
                var name = item.originalFolderName, suffix = 2
                while fm.fileExists(atPath:root.appendingPathComponent(name).path) { name = item.originalFolderName+" (\(suffix))"; suffix += 1 }
                let target = root.appendingPathComponent(name,isDirectory:true), copy = stage.appendingPathComponent(name,isDirectory:true)
                try copyVerified(item.project.folder,to:copy)
                let receipt = json(item.project.folder.deletingLastPathComponent().appendingPathComponent("receipt.json")) ?? [:]
                try rewriteCopy(copy,original:item.project.folder,final:target,library:root)
                if let path = receipt["original_path"] as? String {
                    try rewriteCopy(copy,original:URL(fileURLWithPath:path),final:target,library:root)
                }
                let metadata = receipt["index_record"] as? [String:Any] ?? json(copy.appendingPathComponent("draft_meta_info.json")) ?? [:]
                let record = indexRecord(item.project,metadata:metadata,copied:copy,final:target,library:root)
                try guardClosed(); try unchangedIndex(original)
                try fm.moveItem(at:copy,to:target); added.append(target)
                if !item.project.draftID.isEmpty { entries.removeAll { $0["draft_id"] as? String == item.project.draftID }; ids.insert(item.project.draftID) }
                entries.removeAll { $0["draft_fold_path"] as? String == target.path }
                entries.append(record); restored.append(item); result.completed += 1
            }
            if !added.isEmpty {
                try guardClosed(); try unchangedIndex(original)
                var updated = index; updated["all_draft_store"] = entries; updated["root_path"] = root.path
                updated["draft_ids"] = max((index["draft_ids"] as? Int ?? 0)+added.count,entries.count)
                try saveJSON(updated,to:indexURL)
            }
        } catch { for folder in added { try? fm.removeItem(at:folder) }; throw error }
        // A failure to clean up leaves an extra recoverable copy, never removes
        // the restored project or rolls back its already committed index entry.
        for item in restored { try? fm.removeItem(at:item.project.folder.deletingLastPathComponent()) }
        return result
    }
    func emptyTrash(_ requested:[TrashedCapCutProject]) throws -> ProjectOperationResult {
        try guardClosed()
        let items = try checkedTrashItems(requested)
        var moved:[(URL,URL)] = []
        do {
            for item in items {
                try guardClosed()
                moved.append((item.project.folder,try trashItem(item.project.folder)))
            }
        } catch {
            for (source,trashed) in moved.reversed() where !fm.fileExists(atPath:source.path) { try? fm.moveItem(at:trashed,to:source) }
            throw error
        }
        for item in items { try? fm.removeItem(at:item.project.folder.deletingLastPathComponent()) }
        return ProjectOperationResult(completed:items.count)
    }
    func move(_ projects: [CapCutProject], to parent: URL, includeMedia: Bool = false) throws -> ProjectOperationResult {
        let result = try export(projects,to:parent,includeMedia:includeMedia)
        // Originals enter Trash only after the complete export has been verified.
        do {
            try guardClosed()
            for project in projects {
                guard try manifest(project.folder) == result.sourceFingerprints[project.id] else {
                    throw LauncherError.message("Список проектов изменился. Обновите его и повторите действие.")
                }
            }
            _ = try trash(projects)
        } catch {
            throw LauncherError.message("Копия сохранена в \(result.destination!.path). Оригиналы не перенесены: \(error.localizedDescription)")
        }
        return result
    }
    func importProjects(from source: URL) throws -> ProjectOperationResult {
        try guardClosed()
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard source.path != canonicalRoot.path, !source.path.hasPrefix(canonicalRoot.path+"/") else { throw LauncherError.message("Этот проект уже находится в текущей библиотеке.") }
        let sourceLibrary = ProjectLibrary(root:source,backups:backups,isCapCutRunning:isCapCutRunning)
        let single = fm.fileExists(atPath:source.appendingPathComponent("draft_meta_info.json").path)
        let projects: [CapCutProject]
        if single {
            let parent = ProjectLibrary(root:source.deletingLastPathComponent(),backups:backups,isCapCutRunning:isCapCutRunning)
            projects = try parent.scan().filter { $0.folder.resolvingSymlinksInPath().standardizedFileURL.path == source.path }
        } else { projects = try sourceLibrary.scan() }
        guard !projects.isEmpty else { throw LauncherError.message("В выбранной папке нет распознанных проектов CapCut.") }
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        let (original,index) = try safeIndex(); try backupIndex(original)
        let existing = try scan(); var ids = Set(existing.map(\.draftID).filter { !$0.isEmpty })
        var entries = index["all_draft_store"] as? [[String:Any]] ?? []
        var result = ProjectOperationResult(); var added:[URL] = []
        let staging = root.appendingPathComponent(".capcut-import-"+UUID().uuidString)
        try fm.createDirectory(at:staging,withIntermediateDirectories:false)
        defer { try? fm.removeItem(at:staging) }
        do {
            for project in projects {
                if !project.draftID.isEmpty && ids.contains(project.draftID) { result.skipped += 1; continue }
                guard !project.incomplete, !project.draftID.isEmpty else { result.skipped += 1; continue }
                var name = project.id, suffix = 2
                while fm.fileExists(atPath:root.appendingPathComponent(name).path) { name = project.id + " (\(suffix))"; suffix += 1 }
                let target = root.appendingPathComponent(name), copy = staging.appendingPathComponent(name)
                try copyVerified(project.folder,to:copy)
                try ProjectAssets().validatePortable(in:copy)
                try rewriteCopy(copy,original:project.folder,final:target,library:root)
                guard let meta = json(copy.appendingPathComponent("draft_meta_info.json")) else { throw LauncherError.message("В выбранной папке нет распознанных проектов CapCut.") }
                try guardClosed(); try unchangedIndex(original)
                let record = indexRecord(project,metadata:meta,copied:copy,final:target,library:root)
                try fm.moveItem(at:copy,to:target); added.append(target)
                entries.removeAll { $0["draft_id"] as? String == project.draftID }
                entries.append(record)
                ids.insert(project.draftID); result.completed += 1
            }
            if !added.isEmpty {
                try guardClosed(); try unchangedIndex(original)
                var updated = index; updated["all_draft_store"] = entries; updated["root_path"] = root.path
                updated["draft_ids"] = max((index["draft_ids"] as? Int ?? 0)+added.count,entries.count)
                try saveJSON(updated,to:indexURL)
            }
        } catch { for folder in added { try? fm.removeItem(at:folder) }; throw error }
        return result
    }
}
