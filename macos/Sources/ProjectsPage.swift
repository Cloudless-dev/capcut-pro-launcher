import SwiftUI
import AppKit

struct ProjectsPage:View {
    @ObservedObject private var interface = InterfacePreferences.shared
    @ObservedObject var model:LauncherModel
    @ObservedObject var manager:ProjectManager
    @Environment(\.veil) private var palette
    @ViewState private var showLocation = false
    var body:some View {
        VStack(alignment:.leading,spacing:V(20)) {
            ViewThatFits(in:.horizontal) {
                HStack(spacing:V(12)) { tabs; Spacer(minLength:V(12)); transfer }
                VStack(alignment:.leading,spacing:V(12)) { tabs; transfer }
            }
            if !manager.message.isEmpty {
                HStack(alignment:.top,spacing:V(10)) {
                    Label(L(manager.message),systemImage:manager.working ? "hourglass" : manager.isError ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.veil(size:12)).foregroundStyle(manager.isError ? Color.red : Color.secondary).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:V(8))
                    if !manager.working {
                        Button { manager.clearMessage() } label: { Image(systemName:"xmark") }
                            .buttonStyle(VeilIconStyle()).help(L("Закрыть уведомление")).accessibilityLabel(L("Закрыть уведомление"))
                    }
                }.surface(padding:12)
            }
            if manager.showingTrash { ProjectTrashContent(manager:manager) }
            else {
                if manager.projects.isEmpty && !manager.loading {
                    VStack(spacing:V(12)) {
                        Image(systemName:"film.stack").font(.veil(size:34,weight:.light)).foregroundStyle(palette.accent)
                        Text(L("Проектов пока нет")).font(.veil(size:17,weight:.semibold))
                        Text(L("Выберите другую папку или импортируйте проекты из сохранённой копии."))
                            .font(.veil(size:12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth:.infinity).padding(.vertical,V(35)).surface()
                } else {
                    HStack {
                        Button { manager.toggleAll() } label: {
                            Label(L(manager.selected.count == manager.projects.count ? "Снять выделение" : "Выбрать все"),systemImage:manager.selected.count == manager.projects.count ? "checkmark.circle.fill" : "circle")
                        }.buttonStyle(.plain)
                        Spacer()
                        Text(manager.selected.isEmpty ? L("Всего: \(manager.projects.count)") : L("Выбрано: \(manager.selected.count)"))
                            .foregroundStyle(.secondary)
                    }.font(.veil(size:11))
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:V(235)),spacing:V(18),alignment:.top)],alignment:.leading,spacing:V(18)) {
                        ForEach(manager.projects) { project in ProjectCard(manager:manager,project:project) }
                    }
                    ViewThatFits(in:.horizontal) {
                        HStack(spacing:V(10)) { move; Spacer(minLength:V(10)); deletion }
                        VStack(alignment:.leading,spacing:V(10)) { move; deletion }
                    }
                    Text(L("Операции с файлами доступны при закрытом CapCut. Без выделения экспортируются все проекты. Повторные и неполные проекты при импорте пропускаются."))
                        .font(.veil(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
                DisclosureGroup(isExpanded:$showLocation) {
                    VStack(alignment:.leading,spacing:V(12)) {
                        Text(manager.root.path).font(.veil(size:11,design:.monospaced)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                        Text(L("Экспортируйте только проект или соберите копию со всеми материалами. При импорте ссылки на собранные файлы обновятся автоматически."))
                            .font(.veil(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        HStack(spacing:V(10)) {
                            Button { manager.chooseRoot { model.document.settings.projectsRoot = $0; model.persist() } } label: { Text(L("Изменить…")) }
                            Button { manager.reveal() } label: { Label(L("Открыть в Finder"),systemImage:"folder") }
                        }.buttonStyle(VeilButtonStyle())
                    }.padding(.top,V(12))
                } label: { Label(L("Папка проектов"),systemImage:"folder").font(.veil(size:12,weight:.medium)) }
                    .surface(padding:16)
            }
        }.disabled(manager.working).onAppear {
            manager.setRoot(model.document.settings.projectsRoot ?? URL(fileURLWithPath:model.document.settings.dataRoot).appendingPathComponent("Projects/com.lveditor.draft").path)
        }
    }
    var tabs:some View {
        HStack(spacing:V(3)) {
            sectionButton("Мои проекты",count:manager.projects.count,trash:false)
            sectionButton("Корзина",count:manager.trashItems.count,trash:true)
        }.padding(V(4)).background(palette.accent.opacity(0.08),in:RoundedRectangle(cornerRadius:V(15)))
    }
    @ViewBuilder var transfer:some View {
        HStack(spacing:V(8)) {
            if manager.loading || manager.working { ProgressView().controlSize(.small) }
            Button { manager.clearMessage(); manager.refresh() } label: { Image(systemName:"arrow.clockwise") }
                .buttonStyle(VeilIconStyle()).help(L("Обновить список")).accessibilityLabel(L("Обновить список"))
            if !manager.showingTrash {
                Button { manager.importProjects() } label: { Label(L("Импорт"),systemImage:"square.and.arrow.down") }.buttonStyle(VeilButtonStyle())
                Button { manager.exportProjects() } label: { Label(L("Экспорт"),systemImage:"square.and.arrow.up") }
                    .buttonStyle(VeilButtonStyle(prominent:true)).disabled(manager.projects.isEmpty)
            }
        }
    }
    var move:some View {
        Button { manager.exportProjects(move:true) } label: { Label(L("Перенести в папку…"),systemImage:"folder") }
            .buttonStyle(LauncherActionStyle(destructive:true)).help(L("Сохранить копию в другой папке и отправить оригиналы в корзину лаунчера.")).disabled(manager.selected.isEmpty)
    }
    var deletion:some View {
        HStack(spacing:V(8)) {
            Button(L("Удалить выбранные"),role:.destructive) { manager.deleteProjects(manager.chosen) }
                .buttonStyle(LauncherActionStyle(destructive:true)).disabled(manager.selected.isEmpty)
            Button(L("Удалить все"),role:.destructive) { manager.deleteProjects(manager.projects) }.buttonStyle(LauncherActionStyle(destructive:true))
        }
    }
    func sectionButton(_ title:String,count:Int,trash:Bool)->some View {
        let active = manager.showingTrash == trash
        return Button { manager.showTrash(trash) } label: {
            HStack(spacing:V(7)) {
                Text(L(title))
                Text("\(count)").font(.veil(size:10,weight:.semibold)).padding(.horizontal,V(5)).padding(.vertical,V(2))
                    .background(palette.accent.opacity(0.15),in:Capsule())
            }.font(.veil(size:11,weight:.medium)).padding(.horizontal,V(11)).padding(.vertical,V(9))
                .foregroundStyle(active ? Color.primary : .secondary)
                .background(active ? palette.card : .clear,in:RoundedRectangle(cornerRadius:V(11)))
                .overlay(RoundedRectangle(cornerRadius:V(11)).strokeBorder(active ? palette.border : .clear,lineWidth:1))
        }.buttonStyle(.plain).accessibilityLabel(L(title)+", "+String(count))
    }
}

struct ProjectCard:View {
    @ObservedObject private var interface = InterfacePreferences.shared
    @ObservedObject var manager:ProjectManager
    let project:CapCutProject
    @Environment(\.veil) private var palette
    var selected:Bool { manager.selected.contains(project.id) }
    var body:some View {
        VStack(alignment:.leading,spacing:V(0)) {
            Button { manager.toggle(project.id) } label: {
                VStack(alignment:.leading,spacing:V(12)) {
                    Color.clear.aspectRatio(1.65,contentMode:.fit)
                        .overlay {
                            if let image = manager.thumbnails[project.id] { Image(nsImage:image).resizable().scaledToFill() }
                            else { ZStack { palette.accent.opacity(0.08); Image(systemName:"film").font(.veil(size:30,weight:.light)).foregroundStyle(palette.accent) } }
                        }.clipped().clipShape(RoundedRectangle(cornerRadius:V(14)))
                        .overlay(alignment:.topLeading) {
                            Image(systemName:selected ? "checkmark.circle.fill" : "circle")
                                .font(.veil(size:20)).symbolRenderingMode(.palette)
                                .foregroundStyle(selected ? palette.accent : .white,Color.black.opacity(0.55))
                                .padding(V(9))
                        }
                    Text(project.name).font(.veil(size:15,weight:.semibold)).lineLimit(2).padding(.horizontal,V(12))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(L("Выбрать проект")+" "+project.name)
            HStack(spacing:V(5)) {
                VStack(alignment:.leading,spacing:V(4)) {
                    Text(project.modified,format:.dateTime.day().month().year()).font(.veil(size:10))
                    Text(ByteCountFormatter.string(fromByteCount:project.byteCount,countStyle:.file)).font(.veil(size:10))
                    if project.incomplete { Text(L("Неполные данные проекта")).font(.veil(size:10)).foregroundStyle(.orange) }
                }.foregroundStyle(.secondary)
                Spacer(minLength:V(0))
                Button { manager.reveal(project) } label: { Image(systemName:"folder") }
                    .buttonStyle(VeilIconStyle()).help(L("Открыть в Finder")).accessibilityLabel(L("Открыть в Finder"))
                Button(role:.destructive) { manager.deleteProjects([project]) } label: { Image(systemName:"trash") }
                    .buttonStyle(VeilIconStyle(destructive:true)).help(L("Удалить проект")).accessibilityLabel(L("Удалить проект")+" "+project.name)
            }.padding(.horizontal,V(12)).padding(.vertical,V(10))
        }.surface(padding:0,selected:selected)
    }
}

struct ProjectTrashContent: View {
    @ObservedObject private var interface = InterfacePreferences.shared
    @ObservedObject var manager:ProjectManager
    var body: some View {
        VStack(alignment:.leading,spacing:V(18)) {
            Text(L("Здесь хранятся удалённые проекты этой библиотеки. «Восстановить» вернёт папку, обновит пути и список CapCut. Автоматической очистки нет."))
                .font(.veil(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                if !manager.trashItems.isEmpty {
                    Button { manager.restoreProjects(manager.selectedTrash.isEmpty ? manager.trashItems : manager.chosenTrash) } label: {
                        Label(L(manager.selectedTrash.isEmpty ? "Восстановить все" : "Восстановить выбранные"),systemImage:"arrow.uturn.backward")
                    }.buttonStyle(VeilButtonStyle(prominent:true))
                }
                Spacer()
                if manager.loading || manager.working { ProgressView().controlSize(.small) }
                Button { manager.clearMessage(); manager.refresh() } label: { Image(systemName:"arrow.clockwise") }
                    .help(L("Обновить список")).accessibilityLabel(L("Обновить список"))
            }
            if manager.trashItems.isEmpty && !manager.loading {
                VStack(spacing:V(12)) {
                    Image(systemName:"trash").font(.veil(size:34,weight:.light)).foregroundStyle(.secondary)
                    Text(L("Корзина пуста")).font(.veil(size:17,weight:.semibold))
                    Text(L("Удалённые через лаунчер проекты появятся здесь."))
                        .font(.veil(size:12)).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity).padding(.vertical,V(35))
            } else {
                HStack {
                    Button { manager.toggleAllTrash() } label: {
                        Label(L(manager.selectedTrash.count == manager.trashItems.count ? "Снять выделение" : "Выбрать все"),systemImage:manager.selectedTrash.count == manager.trashItems.count ? "checkmark.square.fill" : "square")
                    }.buttonStyle(.plain)
                    Spacer()
                    Text(manager.selectedTrash.isEmpty ? L("Всего: \(manager.trashItems.count)") : L("Выбрано: \(manager.selectedTrash.count)"))
                        .foregroundStyle(.secondary)
                }.font(.veil(size:12))
                ForEach(manager.trashItems) { item in
                    HStack(spacing:V(12)) {
                        Button { manager.toggleTrash(item.id) } label: {
                            Image(systemName:manager.selectedTrash.contains(item.id) ? "checkmark.square.fill" : "square")
                                .font(.veil(size:18)).foregroundStyle(manager.selectedTrash.contains(item.id) ? Color.accentColor : Color.secondary)
                        }.buttonStyle(.plain).accessibilityLabel(L("Выбрать проект")+" "+item.project.name)
                        Group {
                            if let image = manager.trashThumbnails[item.id] { Image(nsImage:image).resizable().scaledToFill() }
                            else { ZStack { Color.primary.opacity(0.04); Image(systemName:"film").foregroundStyle(.secondary) } }
                        }.frame(width:V(80),height:V(52)).clipped().clipShape(RoundedRectangle(cornerRadius:7))
                        VStack(alignment:.leading,spacing:V(5)) {
                            Text(item.project.name).font(.veil(size:13,weight:.semibold)).lineLimit(2)
                            Text(L("Удалён")+" "+item.deleted.formatted(date:.abbreviated,time:.shortened))
                                .font(.veil(size:10)).foregroundStyle(.secondary)
                            Text(ByteCountFormatter.string(fromByteCount:item.project.byteCount,countStyle:.file)).font(.veil(size:10)).foregroundStyle(.tertiary)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        Button { manager.restoreProjects([item]) } label: { Image(systemName:"arrow.uturn.backward") }
                            .buttonStyle(VeilButtonStyle()).help(L("Восстановить проект")).accessibilityLabel(L("Восстановить проект")+" "+item.project.name)
                        Button(role:.destructive) { manager.emptyTrash([item]) } label: { Image(systemName:"trash") }
                            .buttonStyle(LauncherActionStyle(destructive:true)).help(L("В Корзину macOS")).accessibilityLabel(L("В Корзину macOS")+" "+item.project.name)
                    }.padding(V(12)).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
                }
                HStack {
                    Spacer()
                    Button(L(manager.selectedTrash.isEmpty ? "Очистить корзину…" : "Убрать выбранные…"),role:.destructive) {
                        manager.emptyTrash(manager.selectedTrash.isEmpty ? manager.trashItems : manager.chosenTrash)
                    }.buttonStyle(LauncherActionStyle(destructive:true))
                }
                Text(L("Если такой проект уже есть в библиотеке, восстановление пропустит его без перезаписи. Очистка перемещает проекты в системную Корзину macOS."))
                    .font(.veil(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
}
