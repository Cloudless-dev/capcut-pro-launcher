import AppKit
import Combine

@MainActor
final class ProjectManager: ObservableObject {
    @Published var root = URL(fileURLWithPath:NSHomeDirectory()+"/Movies/CapCut/User Data/Projects/com.lveditor.draft")
    @Published var projects:[CapCutProject] = []
    @Published var trashItems:[TrashedCapCutProject] = []
    @Published var showingTrash = false
    @Published var selectedTrash = Set<String>()
    @Published var trashThumbnails:[String:NSImage] = [:]
    @Published var thumbnails:[String:NSImage] = [:]
    @Published var selected = Set<String>()
    @Published var loading = false
    @Published var working = false
    @Published var message = ""
    @Published var isError = false
    private var generation = UUID()
    private let queue = DispatchQueue(label:"app.capcutlauncher.projects",qos:.userInitiated)
    private var backups:URL { URL(fileURLWithPath:NSHomeDirectory()+"/Library/Application Support/CapCut Launcher/ProjectOperations") }
    var chosen:[CapCutProject] { projects.filter { selected.contains($0.id) } }
    var chosenTrash:[TrashedCapCutProject] { trashItems.filter { selectedTrash.contains($0.id) } }
    func showTrash(_ value:Bool) { showingTrash = value; clearMessage() }
    func toggleTrash(_ id:String) { if selectedTrash.contains(id) { selectedTrash.remove(id) } else { selectedTrash.insert(id) } }
    func toggleAllTrash() { selectedTrash = selectedTrash.count == trashItems.count ? [] : Set(trashItems.map(\.id)) }
    var exportSelection:[CapCutProject] { selected.isEmpty ? projects : chosen }
    func setRoot(_ path: String) {
        guard !working else { return }
        let url = URL(fileURLWithPath:(path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
        if root != url { root = url; selected = []; selectedTrash = []; projects = []; trashItems = []; thumbnails = [:]; trashThumbnails = [:]; message = "" }
        refresh()
    }
    func refresh() {
        guard !working else { return }
        let ticket = UUID(); generation = ticket; loading = true
        let library = ProjectLibrary(root:root,backups:backups)
        queue.async {
            let result = Result { (try library.scan(),try library.scanTrash()) }
            Task { @MainActor in
                guard self.generation == ticket else { return }
                self.loading = false
                switch result {
                case .success(let (projects,trash)):
                    self.trashItems = trash
                    self.selectedTrash.formIntersection(Set(trash.map(\.id)))
                    self.trashThumbnails = Dictionary(uniqueKeysWithValues:trash.compactMap { item in
                        item.project.cover.flatMap(NSImage.init(data:)).map { (item.id,$0) }
                    })
                    self.projects = projects
                    self.selected.formIntersection(Set(projects.map(\.id)))
                    self.thumbnails = Dictionary(uniqueKeysWithValues:projects.compactMap { project in
                        project.cover.flatMap(NSImage.init(data:)).map { (project.id,$0) }
                    })
                case .failure(let error): self.message = error.localizedDescription; self.isError = true
                }
            }
        }
    }
    func toggle(_ id: String) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
    func toggleAll() { selected = selected.count == projects.count ? [] : Set(projects.map(\.id)) }
    func reveal(_ project: CapCutProject? = nil) {
        if let project { NSWorkspace.shared.activateFileViewerSelecting([project.folder]) }
        else { NSWorkspace.shared.open(root) }
    }
    private func closed() -> Bool {
        if NativeAccountStore.isCapCutRunning() {
            message = "Сначала полностью закройте CapCut для работы с файлами проектов."; isError = true; return false
        }
        return !working
    }
    private func chooseFolder(_ prompt: String) -> URL? {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true; panel.message = L(prompt)
        return panel.runModal() == .OK ? panel.url : nil
    }
    func chooseRoot(_ save: (String)->Void) {
        guard !working, let url = chooseFolder("Выберите папку с проектами CapCut") else { return }
        clearMessage(); save(url.path); setRoot(url.path)
    }
    func clearMessage() { message = ""; isError = false }
    func exportProjects(move: Bool = false) {
        guard closed(), !exportSelection.isEmpty else { return }
        let list = exportSelection
        clearMessage()
        Task {
            let mode = await AppDialogs.shared.choose(title:"Что включить в копию?",
                message:"Со всеми материалами — видео, аудио, изображения и доступные локальные ресурсы будут собраны внутри копии, а ссылки обновлены. Только проект — исходники останутся по прежним путям.",
                symbol:"shippingbox",actions:[AppDialogAction(title:"Отмена",cancel:true),AppDialogAction(title:"Только проект"),AppDialogAction(title:"Со всеми материалами")])
            guard mode != 0, closed(), let destination = chooseFolder("Выберите, куда сохранить проекты") else { return }
            let includeMedia = mode == 2
            if move {
                let confirmed = await AppDialogs.shared.choose(title:"Перенести проекты: \(list.count)?",
                    message:"Сначала сохраним и проверим копию в выбранной папке. Затем исходные папки проектов отправятся в корзину лаунчера и исчезнут из текущего списка CapCut. Чтобы снова работать с копией в CapCut, используйте «Импорт». Внешние исходники останутся на месте.",
                    names:list.map(\.name),location:destination.path,symbol:"folder",
                    actions:[AppDialogAction(title:"Отмена",cancel:true),AppDialogAction(title:"Перенести",destructive:true)])
                guard confirmed == 1 else { return }
            }
            guard closed() else { return }
            perform { library in try move ? library.move(list,to:destination,includeMedia:includeMedia) : library.export(list,to:destination,includeMedia:includeMedia) }
        }
    }
    func importProjects() {
        guard closed() else { return }
        clearMessage()
        guard let source = chooseFolder("Выберите папку проекта или папку экспорта") else { return }
        perform { try $0.importProjects(from:source) }
    }
    func deleteProjects(_ list:[CapCutProject]) {
        guard closed(), !list.isEmpty else { return }
        clearMessage()
        Task {
            let result = await AppDialogs.shared.choose(title:"В корзину лаунчера проекты: \(list.count)?",
                message:"Проекты исчезнут из списка CapCut и останутся в корзине лаунчера. Во вкладке «Корзина» их можно восстановить одной кнопкой. Облачные проекты и внешние исходники не удаляются.",
                names:list.map(\.name),symbol:"trash",
                actions:[AppDialogAction(title:"Отмена",cancel:true),AppDialogAction(title:"В Корзину",destructive:true)])
            guard result == 1, closed() else { return }
            perform { try $0.trash(list) }
        }
    }
    func restoreProjects(_ items:[TrashedCapCutProject]) {
        guard closed(), !items.isEmpty else { return }
        clearMessage()
        perform { try $0.restore(items) }
    }
    func emptyTrash(_ items:[TrashedCapCutProject]) {
        guard closed(), !items.isEmpty else { return }
        clearMessage()
        Task {
            let result = await AppDialogs.shared.choose(title:"Очистить корзину лаунчера: \(items.count)?",
                message:"Эти проекты будут перемещены в системную Корзину macOS. После этого кнопка восстановления в лаунчере для них будет недоступна. Внешние исходники останутся на месте.",
                names:items.map { $0.project.name },symbol:"trash",
                actions:[AppDialogAction(title:"Отмена",cancel:true),AppDialogAction(title:"В Корзину macOS",destructive:true)])
            guard result == 1, closed() else { return }
            perform { try $0.emptyTrash(items) }
        }
    }
    private func perform(_ operation: @escaping (ProjectLibrary)throws->ProjectOperationResult) {
        generation = UUID(); loading = false; working = true; isError = false; message = "Обрабатываю проекты…"
        let library = ProjectLibrary(root:root,backups:backups)
        queue.async {
            let result = Result { try operation(library) }
            Task { @MainActor in
                self.working = false
                switch result {
                case .success(let report):
                    self.selected = []; self.selectedTrash = []; self.isError = false
                    self.message = "Готово: \(report.completed). Пропущено: \(report.skipped)."
                    if let destination = report.destination { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
                case .failure(let error): self.message = error.localizedDescription; self.isError = true
                }
                self.refresh()
            }
        }
    }
}
