import SwiftUI
import AppKit

struct ProjectsPage: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var manager: ProjectManager
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(spacing:8) {
                sectionButton("Мои проекты",icon:"film.stack",count:manager.projects.count,trash:false)
                sectionButton("Корзина",icon:"trash",count:manager.trashItems.count,trash:true)
                Spacer()
            }
            if !manager.showingTrash {
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Label(L("Папка проектов"),systemImage:"folder").font(.system(size:13,weight:.semibold))
                    Spacer()
                    Button { manager.chooseRoot { model.document.settings.projectsRoot = $0; model.persist() } } label: { Text(L("Изменить…")) }
                    Button { manager.reveal() } label: { Image(systemName:"arrow.up.forward.square") }.help(L("Открыть в Finder")).accessibilityLabel(L("Открыть в Finder"))
                }
                Text(manager.root.path).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                Text(L("Экспортируйте только проект или соберите копию со всеми материалами. При импорте ссылки на собранные файлы обновятся автоматически."))
                    .font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(17).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:13))
            HStack(spacing:10) {
                Button { manager.importProjects() } label: { Label(L("Импорт"),systemImage:"square.and.arrow.down") }.buttonStyle(.bordered)
                Button { manager.exportProjects() } label: {
                    Label(L("Экспорт"),systemImage:"square.and.arrow.up")
                    Text("\(manager.exportSelection.count)").foregroundStyle(.secondary)
                }.buttonStyle(.borderedProminent).disabled(manager.projects.isEmpty)
                Spacer()
                if manager.loading || manager.working { ProgressView().controlSize(.small) }
                Button { manager.clearMessage(); manager.refresh() } label: { Image(systemName:"arrow.clockwise") }.help(L("Обновить список"))
            }
            }
            if !manager.message.isEmpty {
                HStack(alignment:.top,spacing:10) {
                    Label(L(manager.message),systemImage:manager.working ? "hourglass" : manager.isError ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.system(size:12)).foregroundStyle(manager.isError ? Color.red : Color.secondary).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:8)
                    if !manager.working {
                        Button { manager.clearMessage() } label: { Image(systemName:"xmark").font(.system(size:10,weight:.semibold)) }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Закрыть уведомление")).accessibilityLabel(L("Закрыть уведомление"))
                    }
                }.padding(12).background((manager.isError ? Color.red : Color.green).opacity(0.06),in:RoundedRectangle(cornerRadius:10))
            }
            if manager.showingTrash {
                ProjectTrashContent(manager:manager)
            } else if manager.projects.isEmpty && !manager.loading {
                VStack(spacing:12) {
                    Image(systemName:"film.stack").font(.system(size:34,weight:.light)).foregroundStyle(.secondary)
                    Text(L("Проектов пока нет")).font(.system(size:17,weight:.semibold))
                    Text(L("Выберите другую папку или импортируйте проекты из сохранённой копии."))
                        .font(.system(size:12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth:.infinity).padding(.vertical,35)
            } else {
                HStack {
                    Button { manager.toggleAll() } label: {
                        Label(L(manager.selected.count == manager.projects.count ? "Снять выделение" : "Выбрать все"),systemImage:manager.selected.count == manager.projects.count ? "checkmark.square.fill" : "square")
                    }.buttonStyle(.plain)
                    Spacer()
                    Text(manager.selected.isEmpty ? L("Всего: \(manager.projects.count)") : L("Выбрано: \(manager.selected.count)"))
                        .foregroundStyle(.secondary)
                }.font(.system(size:12))
                VStack(spacing:8) {
                    ForEach(manager.projects) { project in
                        HStack(spacing:12) {
                            Button { manager.toggle(project.id) } label: {
                                Image(systemName:manager.selected.contains(project.id) ? "checkmark.square.fill" : "square")
                                    .font(.system(size:18)).foregroundStyle(manager.selected.contains(project.id) ? Color.accentColor : Color.secondary)
                            }.buttonStyle(.plain).accessibilityLabel(L("Выбрать проект")+" "+project.name)
                            thumbnail(project).frame(width:96,height:60).clipped().clipShape(RoundedRectangle(cornerRadius:7))
                            VStack(alignment:.leading,spacing:5) {
                                Text(project.name).font(.system(size:13,weight:.semibold)).lineLimit(2)
                                Text(project.modified,format:.dateTime.day().month().year()).font(.system(size:11)).foregroundStyle(.secondary)
                                Text(ByteCountFormatter.string(fromByteCount:project.byteCount,countStyle:.file)).font(.system(size:10)).foregroundStyle(.tertiary)
                                if project.incomplete { Text(L("Неполные данные проекта")).font(.system(size:10)).foregroundStyle(.orange) }
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            Button { manager.reveal(project) } label: { Image(systemName:"folder") }.help(L("Открыть в Finder")).accessibilityLabel(L("Открыть в Finder"))
                            Button(role:.destructive) { manager.deleteProjects([project]) } label: { Image(systemName:"trash") }.buttonStyle(LauncherActionStyle(destructive:true)).help(L("Удалить проект")).accessibilityLabel(L("Удалить проект")+" "+project.name)
                        }.padding(12).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
                            .overlay(RoundedRectangle(cornerRadius:12).stroke(manager.selected.contains(project.id) ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.06)))
                    }
                }
                HStack(spacing:12) {
                    Button { manager.exportProjects(move:true) } label: { Label(L("Перенести в папку…"),systemImage:"folder") }.buttonStyle(LauncherActionStyle(destructive:true)).help(L("Сохранить копию в другой папке и отправить оригиналы в корзину лаунчера.")).accessibilityLabel(L("Перенести в папку…")).disabled(manager.selected.isEmpty)
                    Spacer()
                    Button(L("Удалить выбранные"),role:.destructive) { manager.deleteProjects(manager.chosen) }.buttonStyle(LauncherActionStyle(destructive:true)).accessibilityLabel(L("Удалить выбранные")).disabled(manager.selected.isEmpty)
                    Button(L("Удалить все"),role:.destructive) { manager.deleteProjects(manager.projects) }.buttonStyle(LauncherActionStyle(destructive:true)).accessibilityLabel(L("Удалить все"))
                }.controlSize(.small)
                Text(L("Операции с файлами доступны при закрытом CapCut. Без выделения экспортируются все проекты. Повторные и неполные проекты при импорте пропускаются."))
                    .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }.disabled(manager.working).onAppear {
            manager.setRoot(model.document.settings.projectsRoot ?? URL(fileURLWithPath:model.document.settings.dataRoot).appendingPathComponent("Projects/com.lveditor.draft").path)
        }
    }
    func sectionButton(_ title:String,icon:String,count:Int,trash:Bool) -> some View {
        Button { manager.showTrash(trash) } label: {
            HStack(spacing:7) {
                Label(L(title),systemImage:icon)
                Text("\(count)").font(.system(size:10,weight:.semibold)).padding(.horizontal,6).padding(.vertical,3)
                    .background(Color.primary.opacity(0.055),in:Capsule())
            }.font(.system(size:12,weight:.medium)).padding(.horizontal,13).padding(.vertical,9)
                .foregroundStyle(manager.showingTrash == trash ? Color.accentColor : Color.secondary)
                .background(manager.showingTrash == trash ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9))
        }.buttonStyle(.plain).accessibilityLabel(L(title)+", "+String(count))
    }
    @ViewBuilder func thumbnail(_ project: CapCutProject) -> some View {
        if let image = manager.thumbnails[project.id] { Image(nsImage:image).resizable().scaledToFill() }
        else { ZStack { Color.primary.opacity(0.045); Image(systemName:"film").font(.system(size:22,weight:.light)).foregroundStyle(.secondary) } }
    }
}

struct ProjectTrashContent: View {
    @ObservedObject var manager:ProjectManager
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text(L("Здесь хранятся удалённые проекты этой библиотеки. «Восстановить» вернёт папку, обновит пути и список CapCut. Автоматической очистки нет."))
                .font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                if !manager.trashItems.isEmpty {
                    Button { manager.restoreProjects(manager.selectedTrash.isEmpty ? manager.trashItems : manager.chosenTrash) } label: {
                        Label(L(manager.selectedTrash.isEmpty ? "Восстановить все" : "Восстановить выбранные"),systemImage:"arrow.uturn.backward")
                    }.buttonStyle(.borderedProminent)
                }
                Spacer()
                if manager.loading || manager.working { ProgressView().controlSize(.small) }
                Button { manager.clearMessage(); manager.refresh() } label: { Image(systemName:"arrow.clockwise") }
                    .help(L("Обновить список")).accessibilityLabel(L("Обновить список"))
            }
            if manager.trashItems.isEmpty && !manager.loading {
                VStack(spacing:12) {
                    Image(systemName:"trash").font(.system(size:34,weight:.light)).foregroundStyle(.secondary)
                    Text(L("Корзина пуста")).font(.system(size:17,weight:.semibold))
                    Text(L("Удалённые через лаунчер проекты появятся здесь."))
                        .font(.system(size:12)).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity).padding(.vertical,35)
            } else {
                HStack {
                    Button { manager.toggleAllTrash() } label: {
                        Label(L(manager.selectedTrash.count == manager.trashItems.count ? "Снять выделение" : "Выбрать все"),systemImage:manager.selectedTrash.count == manager.trashItems.count ? "checkmark.square.fill" : "square")
                    }.buttonStyle(.plain)
                    Spacer()
                    Text(manager.selectedTrash.isEmpty ? L("Всего: \(manager.trashItems.count)") : L("Выбрано: \(manager.selectedTrash.count)"))
                        .foregroundStyle(.secondary)
                }.font(.system(size:12))
                ForEach(manager.trashItems) { item in
                    HStack(spacing:12) {
                        Button { manager.toggleTrash(item.id) } label: {
                            Image(systemName:manager.selectedTrash.contains(item.id) ? "checkmark.square.fill" : "square")
                                .font(.system(size:18)).foregroundStyle(manager.selectedTrash.contains(item.id) ? Color.accentColor : Color.secondary)
                        }.buttonStyle(.plain).accessibilityLabel(L("Выбрать проект")+" "+item.project.name)
                        Group {
                            if let image = manager.trashThumbnails[item.id] { Image(nsImage:image).resizable().scaledToFill() }
                            else { ZStack { Color.primary.opacity(0.04); Image(systemName:"film").foregroundStyle(.secondary) } }
                        }.frame(width:80,height:52).clipped().clipShape(RoundedRectangle(cornerRadius:7))
                        VStack(alignment:.leading,spacing:5) {
                            Text(item.project.name).font(.system(size:13,weight:.semibold)).lineLimit(2)
                            Text(L("Удалён")+" "+item.deleted.formatted(date:.abbreviated,time:.shortened))
                                .font(.system(size:10)).foregroundStyle(.secondary)
                            Text(ByteCountFormatter.string(fromByteCount:item.project.byteCount,countStyle:.file)).font(.system(size:10)).foregroundStyle(.tertiary)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        Button { manager.restoreProjects([item]) } label: { Image(systemName:"arrow.uturn.backward") }
                            .buttonStyle(.bordered).help(L("Восстановить проект")).accessibilityLabel(L("Восстановить проект")+" "+item.project.name)
                        Button(role:.destructive) { manager.emptyTrash([item]) } label: { Image(systemName:"trash") }
                            .buttonStyle(LauncherActionStyle(destructive:true)).help(L("В Корзину macOS")).accessibilityLabel(L("В Корзину macOS")+" "+item.project.name)
                    }.padding(12).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
                }
                HStack {
                    Spacer()
                    Button(L(manager.selectedTrash.isEmpty ? "Очистить корзину…" : "Убрать выбранные…"),role:.destructive) {
                        manager.emptyTrash(manager.selectedTrash.isEmpty ? manager.trashItems : manager.chosenTrash)
                    }.buttonStyle(LauncherActionStyle(destructive:true))
                }
                Text(L("Если такой проект уже есть в библиотеке, восстановление пропустит его без перезаписи. Очистка перемещает проекты в системную Корзину macOS."))
                    .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
}
