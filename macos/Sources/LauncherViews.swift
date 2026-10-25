import SwiftUI
import AppKit

// Explicit type alias keeps the stable property-wrapper API on SDKs that also expose a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

struct LauncherRootView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject private var interface = InterfacePreferences.shared
    @ObservedObject private var dialogs = AppDialogs.shared
    @Environment(\.colorScheme) private var scheme
    var palette:VeilPalette { VeilPalette(theme:interface.theme,dark:scheme == .dark) }
    var body: some View {
        HStack(spacing:V(0)) {
            sidebar.frame(width:V(186))
            Rectangle().fill(palette.border.opacity(0.35)).frame(width:V(1))
            VStack(spacing:V(0)) {
                header
                PageScrollView(page:model.destination) {
                    Group {
                        switch model.destination {
                        case "projects": ProjectsPage(model:model,manager:model.projects)
                        case "guide": GuidePage(model:model)
                        case "settings": SettingsPage(model:model)
                        case "about": AboutPage(version:model.version)
                        default: ProfilesPage(model:model)
                        }
                    }.padding(.horizontal,V(28)).padding(.bottom,V(28)).padding(.top,V(8))
                        .frame(maxWidth:V(1200),alignment:.topLeading).frame(maxWidth:.infinity)
                }.id(interface.effectiveLanguage).frame(maxWidth:.infinity,maxHeight:.infinity)
                if model.destination == "profiles", model.selectedProfile != nil { LaunchBar(model:model) }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }
        .background(palette.canvas).ignoresSafeArea(.container,edges:.top)
        .disabled(dialogs.current != nil).accessibilityHidden(dialogs.current != nil)
        .overlay { AppDialogOverlay() }
        .sheet(isPresented:$model.profileEditorVisible) { ProfileEditor(model:model).veilContext() }
        .veilContext()
        .onAppear { model.checkSelectedSession() }
    }
    var sidebar: some View {
        VStack(alignment:.leading,spacing:V(20)) {
            HStack(spacing:V(10)) {
                Image(systemName:"play.rectangle.on.rectangle").font(.veil(size:25,weight:.medium)).foregroundStyle(palette.accent)
                Text("Launcher").font(.veil(size:16,weight:.semibold))
            }.padding(.horizontal,V(8)).padding(.top,V(42)).padding(.bottom,V(12))
            VStack(spacing:V(9)) {
                navigation("profiles",title:L("Профили"),icon:"person")
                navigation("projects",title:L("Проекты"),icon:"folder")
                navigation("guide",title:L("Инструкция"),icon:"book")
                navigation("settings",title:L("Настройки"),icon:"gearshape")
                navigation("about",title:L("О лаунчере"),icon:"info.circle")
            }
            Spacer(minLength:V(20))
            if let active = model.runningProfile {
                HStack(spacing:V(7)) {
                    Circle().fill(Color.green).frame(width:V(6),height:V(6))
                    VStack(alignment:.leading,spacing:V(3)) {
                        Text(L("CapCut открыт")).font(.veil(size:11,weight:.medium))
                        Text(active.name).font(.veil(size:11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.padding(.horizontal,V(8))
            }
            VStack(spacing:V(14)) {
                Rectangle().fill(palette.border).frame(height:V(1))
                HStack {
                    Text(L("Версия \(model.version)")).font(.veil(size:10)).foregroundStyle(.secondary)
                    Spacer(minLength:V(0))
                    UpdatesButton(updates:model.updates,version:model.version)
                }
            }.padding(.horizontal,V(5))
        }.padding(.horizontal,V(14)).padding(.bottom,V(20)).frame(maxHeight:.infinity)
            .background(LinearGradient(colors:[palette.sidebar,palette.sidebar.opacity(0.65)],startPoint:.topLeading,endPoint:.bottomTrailing))
    }
    func navigation(_ id:String,title:String,icon:String) -> some View {
        let selected = model.destination == id
        return Button { model.destination = id } label: {
            HStack(spacing:V(12)) {
                Image(systemName:icon).font(.veil(size:19,weight:.regular)).frame(width:V(23))
                Text(title).font(.veil(size:13,weight:selected ? .semibold : .regular))
                Spacer(minLength:V(0))
            }.padding(.horizontal,V(13)).padding(.vertical,V(15))
                .foregroundStyle(selected ? palette.accent : Color.primary.opacity(0.8))
                .background(selected ? palette.accent.opacity(palette.light ? 0.10 : 0.17) : .clear,in:RoundedRectangle(cornerRadius:V(17)))
                .overlay(RoundedRectangle(cornerRadius:V(17)).strokeBorder(selected ? palette.border : .clear,lineWidth:1))
                .contentShape(RoundedRectangle(cornerRadius:V(17)))
        }.buttonStyle(.plain)
    }
    var header: some View {
        HStack(spacing:V(18)) {
            Text(model.destination == "projects" ? L("Проекты") : model.destination == "settings" ? L("Настройки") : model.destination == "guide" ? L("Инструкция") : model.destination == "about" ? L("О лаунчере") : L("Профили"))
                .font(.veil(size:29,weight:.bold)).lineLimit(1)
            Spacer(minLength:V(0))
            if model.destination == "profiles" {
                Button { model.addProfile() } label: { Label(L("Добавить профиль"),systemImage:"plus") }
                    .buttonStyle(VeilButtonStyle()).disabled(model.busy)
            }
        }.padding(.horizontal,V(28)).padding(.top,V(39)).padding(.bottom,V(24))
    }
}

struct ProfilesPage: View {
    @ObservedObject private var interface = InterfacePreferences.shared
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(alignment:.leading,spacing:V(18)) {
            if model.document.profiles.isEmpty {
                VStack(spacing:V(14)) {
                    Image(systemName:"person.crop.circle.badge.plus").font(.veil(size:36,weight:.light)).foregroundStyle(Color.accentColor)
                    Text(L("Первый профиль")).font(.veil(size:19,weight:.semibold))
                    Text(L("Выберите вход по почте или текущий аккаунт CapCut.\nДля каждого профиля можно сохранить свой регион."))
                        .font(.veil(size:13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(L("Создать профиль")) { model.addProfile() }.buttonStyle(VeilButtonStyle(prominent:true)).controlSize(.large)
                }.frame(maxWidth:.infinity).padding(.vertical,V(60)).surface()
            } else {
                VStack(spacing:V(16)) {
                    ForEach(model.document.profiles) { profile in
                        ProfileRow(model:model,profile:profile,selected:model.document.selectedProfileID == profile.id,
                            running:model.runningProfileID == profile.id,checking:model.checkingProfiles.contains(profile.id) || model.browserProfileID == profile.id) {
                                model.changeProfile(profile.id)
                            }.contextMenu {
                                Button(L("Редактировать профиль"),systemImage:"pencil") { model.renameProfile(profile) }.disabled(model.busy)
                                Button(L("Войти заново"),systemImage:"arrow.clockwise") { model.signIn(profile.id) }.disabled(model.busy)
                                Divider()
                                Button(L("Удалить профиль"),systemImage:"trash",role:.destructive) { model.deleteProfile(profile) }
                                    .disabled(model.runningProfileID == profile.id || model.browserProfileID == profile.id)
                            }
                    }
                }
            }
        }
    }
}

struct ProfileRow: View {
    @ObservedObject private var interface = InterfacePreferences.shared
    @ObservedObject var model: LauncherModel
    @Environment(\.veil) private var palette
    let profile:LauncherProfile
    let selected:Bool
    let running:Bool
    let checking:Bool
    let select:()->Void
    var subtitle:String {
        if profile.usesCapCutAccount { return profile.accountLabel.isEmpty ? L("Текущий аккаунт CapCut") : profile.accountLabel + " · CapCut" }
        return profile.accountLabel.isEmpty ? L("Вход ещё не выполнен") : profile.accountLabel
    }
    var body:some View {
        HStack(spacing:V(12)) {
            Button(action:select) {
                Text(String(profile.name.prefix(1)).uppercased()).font(.veil(size:22,weight:.medium))
                    .foregroundStyle(palette.accent).frame(width:V(54),height:V(54))
                    .background(palette.accent.opacity(0.14),in:Circle())
                    .overlay(Circle().strokeBorder(palette.border,lineWidth:1))
            }.buttonStyle(.plain).accessibilityLabel(L("Выбрать профиль")+" "+profile.name)
            VStack(alignment:.leading,spacing:V(8)) {
                Button(action:select) {
                    HStack(spacing:V(8)) {
                        Text(profile.name).font(.veil(size:18,weight:.semibold)).lineLimit(1)
                        if running { Text(L("ОТКРЫТ")).font(.veil(size:8,weight:.bold)).foregroundStyle(.green) }
                        Spacer(minLength:V(0))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                Text(subtitle).font(.veil(size:11)).foregroundStyle(.secondary).lineLimit(1)
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:V(15)) { region; auth }
                    VStack(alignment:.leading,spacing:V(6)) { region; auth }
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            actions
        }.surface(padding:20,selected:selected)
            .overlay(alignment:.leading) {
                if selected { RoundedRectangle(cornerRadius:2).fill(palette.accent).frame(width:V(4)).padding(.vertical,V(14)) }
            }
            .accessibilityElement(children:.contain)
    }
    var region:some View {
        RegionPicker(code:Binding(get:{profile.region},set:{_ = model.setRegion($0,profileID:profile.id)}))
            .disabled(model.browserProfileID == profile.id || model.launching)
    }
    @ViewBuilder var auth:some View {
        if checking { HStack(spacing:V(6)) { ProgressView().controlSize(.mini); Text(L("Проверяю вход на сервере")).font(.veil(size:10)).foregroundStyle(.secondary) } }
        else { AuthBadge(state:profile.authState) }
    }
    var actions:some View {
        HStack(spacing:V(2)) {
            Button { model.checkSelectedProfile(profile.id) } label: {
                if checking { ProgressView().controlSize(.small).frame(width:V(15),height:V(15)) }
                else { Image(systemName:"arrow.clockwise") }
            }
                .buttonStyle(VeilIconStyle()).help(L("Проверить сессию")).accessibilityLabel(L("Проверить сессию")).disabled(checking || model.browserProfileID != nil || model.launching || running)
            Button { model.renameProfile(profile) } label: { Image(systemName:"pencil") }
                .buttonStyle(VeilIconStyle()).help(L("Редактировать профиль")).accessibilityLabel(L("Редактировать профиль")).disabled(model.busy)
            Button(role:.destructive) { model.deleteProfile(profile) } label: { Image(systemName:"trash") }
                .buttonStyle(VeilIconStyle(destructive:true)).help(L("Удалить профиль")).accessibilityLabel(L("Удалить профиль")).disabled(running || model.browserProfileID == profile.id)
        }
    }

}

struct AuthBadge:View {
    @ObservedObject private var interface = InterfacePreferences.shared
    let state:ProfileAuthState
    var color:Color { state == .valid ? .green : (state == .expired || state == .needsLogin || state == .signedOut) ? .orange : .secondary }
    var body:some View {
        HStack(spacing:V(6)) {
            Circle().fill(color).frame(width:V(7),height:V(7))
            Text(L(state.title)).foregroundStyle(.secondary)
        }.font(.veil(size:10,weight:.medium)).fixedSize(horizontal:true,vertical:false)
    }
}

struct LaunchBar:View {
    @ObservedObject private var interface = InterfacePreferences.shared
    @ObservedObject var model:LauncherModel
    @Environment(\.veil) private var palette
    var body:some View {
        VStack(spacing:V(0)) {
            Rectangle().fill(palette.border).frame(height:V(1))
            ViewThatFits(in:.horizontal) {
                HStack(spacing:V(20)) { status; Spacer(minLength:V(12)); launch }
                VStack(alignment:.leading,spacing:V(12)) { status; launch.frame(maxWidth:.infinity,alignment:.trailing) }
            }.padding(.vertical,V(22))
        }.padding(.horizontal,V(28)).background(palette.canvas)
    }
    var status:some View {
        VStack(alignment:.leading,spacing:V(6)) {
            HStack(spacing:V(8)) {
                if model.launching { ProgressView().controlSize(.mini) }
                else { Circle().fill(model.statusIsError ? Color.orange : model.selectedProfile?.authState == .valid ? .green : .secondary).frame(width:V(8),height:V(8)) }
                Text(L(model.statusIsError || model.launching || model.runningProfileID != nil ? model.status : model.selectedProfile?.authState.title ?? model.status))
                    .font(.veil(size:12,weight:.semibold)).lineLimit(2)
            }
            if let profile = model.selectedProfile {
                Text(profile.name+" · "+L("Регион: \(model.runningProfileID == profile.id && !model.observedRegion.isEmpty ? model.observedRegion : profile.region)"))
                    .font(.veil(size:11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
    @ViewBuilder var launch:some View {
        if let profile = model.selectedProfile {
            Button { model.startCapCut(profile.id) } label: {
                Label(model.launching ? L("Запускаю…") : model.runningProfileID == profile.id ? L("Показать CapCut") : profile.usesCapCutAccount && (profile.authState == .signedOut || profile.authState == .expired || profile.authState == .needsLogin) ? L("Открыть CapCut для входа") : L("Запустить CapCut"),systemImage:model.runningProfileID == profile.id ? "arrow.up.right.square" : "play.fill")
                    .font(.veil(size:15,weight:.semibold)).padding(.horizontal,V(20)).padding(.vertical,V(7))
            }.buttonStyle(VeilButtonStyle(prominent:true))
                .disabled(model.launching || model.browser != nil || model.runningProfileID != nil && model.runningProfileID != profile.id || model.runningProfileID == nil && ((!profile.usesCapCutAccount && profile.authState != .valid) || model.checkingProfiles.contains(profile.id)))
        }
    }
}

struct ProfileEditor: View {
    @ObservedObject private var interface = InterfacePreferences.shared
    @Environment(\.veil) private var palette
    @ObservedObject var model: LauncherModel
    @ObservedObject private var dialogs = AppDialogs.shared
    @FocusState var focused: Bool
    var body: some View {
        VStack(alignment:.leading,spacing:V(18)) {
            Label(model.editingProfileID == nil ? L("Новый профиль") : L("Редактировать профиль"),systemImage:model.editingProfileID == nil ? "person.crop.circle.badge.plus" : "pencil")
                .font(.veil(size:19,weight:.semibold))
            TextField(L("Название профиля"),text:$model.profileNameDraft).textFieldStyle(.roundedBorder).focused($focused).onSubmit { model.saveProfileName() }
            Picker(L("Способ входа"),selection:$model.profileMethodDraft) {
                Text(L("Вход через лаунчер")).tag(ProfileSignInMethod.launcher)
                Text(L("Текущий аккаунт CapCut")).tag(ProfileSignInMethod.capcut)
            }.pickerStyle(.menu)
            VStack(alignment:.leading,spacing:V(7)) {
                Label(L("Регион"),systemImage:"globe.europe.africa").font(.veil(size:12,weight:.medium))
                RegionPicker(code:$model.profileRegionDraft)
                Text(L("Или введите код любой страны, например US.")).font(.veil(size:11)).foregroundStyle(.secondary)
            }
            Divider()
            if model.profileMethodDraft == .capcut {
                Label(L("Используется текущий вход приложения CapCut. Почта и пароль в лаунчере не нужны."),systemImage:"person.crop.circle.badge.checkmark")
                    .font(.veil(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text(L("Если входа нет, откройте CapCut из этого профиля и войдите официальным способом — например, через Google. Выбранный регион уже будет применён."))
                    .font(.veil(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text(L("Профили этого типа используют один текущий аккаунт приложения CapCut."))
                    .font(.veil(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            } else {
              Toggle(L("Автоматический вход"),isOn:$model.profileAutomaticDraft).toggleStyle(.switch)
              if model.profileAutomaticDraft {
                TextField(L("Почта CapCut"),text:$model.profileEmailDraft).textFieldStyle(.roundedBorder)
                SecureField(model.profileHasPassword ? L("Новый пароль (необязательно)") : L("Пароль CapCut"),text:$model.profilePasswordDraft).textFieldStyle(.roundedBorder)
                Label(L("Пароль сохраняется в Связке ключей этого Mac. Вход выполняется на сайте CapCut в фоне."),systemImage:"lock.shield")
                    .font(.veil(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            } else {
                Text(L("Вход выполняется через окно комплектного браузера.")).font(.veil(size:12)).foregroundStyle(.secondary)
              }
              if let id = model.editingProfileID {
                Button(L("Войти через браузер")) { model.dismissProfileEditor(); model.signIn(id,manualBrowser:true) }.disabled(model.busy)
              }
            }
            if !model.editorError.isEmpty { Text(L(model.editorError)).font(.veil(size:11)).foregroundStyle(.orange) }
            HStack { Spacer(); Button(L("Отмена")) { model.dismissProfileEditor() }.keyboardShortcut(.cancelAction)
                Button(model.editorNeedsSignIn ? L("Сохранить и войти") : L("Сохранить")) { model.saveProfileName() }.buttonStyle(VeilButtonStyle(prominent:true)).keyboardShortcut(.defaultAction)
                    .disabled(model.profileNameDraft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.profileMethodDraft != .capcut && model.profileAutomaticDraft && (model.profileEmailDraft.isEmpty || model.profilePasswordDraft.isEmpty && !model.profileHasPassword)) }
        }.padding(V(28)).frame(width:V(470)).onAppear { focused = true }.onDisappear { model.profilePasswordDraft = "" }
            .disabled(dialogs.current != nil).accessibilityHidden(dialogs.current != nil)
            .overlay { AppDialogOverlay() }
            .background(palette.canvas)
    }
}

struct SettingsPage: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject private var interface = InterfacePreferences.shared
    var body: some View {
        VStack(alignment:.leading,spacing:V(20)) {
            VStack(alignment:.leading,spacing:V(18)) {
                Label(L("Оформление"),systemImage:"paintpalette").font(.veil(size:14,weight:.semibold))
                HStack {
                    Text(L("Язык интерфейса")); Spacer()
                    Picker(L("Язык интерфейса"),selection:$interface.language) {
                        Text(L("Системный")).tag("system")
                        Text("Русский").tag("ru")
                        Text("English").tag("en")
                    }.labelsHidden().frame(width:V(180))
                }
                Divider()
                HStack {
                    Text(L("Тема")); Spacer()
                    Picker(L("Тема"),selection:$interface.theme) {
                        Text(L("Системная")).tag("system")
                        Text(L("Светлая")).tag("light")
                        Text(L("Серая")).tag("gray")
                        Text(L("Тёмная")).tag("dark")
                    }.labelsHidden().frame(width:V(180))
                }
                Divider()
                HStack {
                    Text(L("Размер интерфейса")); Spacer()
                    Picker(L("Размер интерфейса"),selection:$interface.interfaceSize) {
                        Text(L("Маленький")).tag("small")
                        Text(L("Средний")).tag("medium")
                        Text(L("Большой")).tag("large")
                    }.labelsHidden().frame(width:V(180))
                }
                Text(L("Размер текста, кнопок и отступов изменяется сразу.")).font(.veil(size:11)).foregroundStyle(.secondary)
                Text(L("По умолчанию язык и тема соответствуют настройкам macOS.")).font(.veil(size:11)).foregroundStyle(.secondary)
            }.surface()
            VStack(alignment:.leading,spacing:V(20)) {
                Label(L("Поведение лаунчера"),systemImage:"switch.2").font(.veil(size:14,weight:.semibold))
                settingToggle(L("Запуск после авторизации"),
                    description:L("Автоматически открывать CapCut после успешного входа в браузере."),
                    value:Binding(get:{model.document.settings.autoStartAfterAuth},set:model.setAutoStart))
                Divider()
                settingToggle(L("Автообновления"),
                    description:L("Проверять и загружать новые версии автоматически."),
                    value:Binding(get:{model.document.settings.automaticUpdates},set:model.setAutomaticUpdates))
                if !model.updates.configured { Text(L("В этой локальной сборке обновления пока не опубликованы. Настройка сохранится для будущих версий.")).font(.veil(size:11)).foregroundStyle(.secondary) }
            }.surface()
            VStack(alignment:.leading,spacing:V(18)) {
                Label(L("Расположение файлов"),systemImage:"folder").font(.veil(size:14,weight:.semibold))
                pathRow(L("Приложение CapCut"),path:model.document.settings.appPath,choose:model.chooseApp)
                Divider()
                pathRow(L("Данные CapCut"),path:model.document.settings.dataRoot,choose:model.chooseData)
                Text(L("Нажмите карандаш у профиля, чтобы изменить регион и настройки входа. Круглая стрелка проверяет сессию, красная корзина удаляет профиль."))
                    .font(.veil(size:12)).foregroundStyle(.secondary)
                Button { model.openProjects() } label: { Label(L("Открыть локальные проекты"),systemImage:"folder.badge.gearshape") }.buttonStyle(VeilButtonStyle())
            }.surface()
            HStack(alignment:.top,spacing:V(12)) {
                Image(systemName:"lock.shield").font(.veil(size:18)).foregroundStyle(.secondary)
                Text(L("Входы хранятся в Keychain macOS. Браузерные данные разделены по профилям. Локальные проекты CapCut остаются общими."))
                    .font(.veil(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(.horizontal,V(4))
        }
    }
    func settingToggle(_ title:String,description:String,value:Binding<Bool>) -> some View {
        HStack(alignment:.center,spacing:V(24)) {
            VStack(alignment:.leading,spacing:V(5)) {
                Text(L(title)).font(.veil(size:13,weight:.medium))
                Text(L(description)).font(.veil(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading)
            Toggle(title,isOn:value).labelsHidden().toggleStyle(.switch)
                .fixedSize().accessibilityLabel(L(title)).accessibilityHint(L(description))
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    func pathRow(_ title:String,path:String,choose:@escaping ()->Void) -> some View {
        HStack(spacing:V(15)) {
            VStack(alignment:.leading,spacing:V(6)) {
                Text(L(title)).font(.veil(size:12,weight:.medium))
                Text(path).font(.veil(size:11,design:.monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer(minLength:V(10))
            Button(L("Выбрать…"),action:choose).disabled(model.busy)
        }
    }
}

struct GuidePage: View {
    @ObservedObject private var interface = InterfacePreferences.shared
    let model: LauncherModel
    let steps = [
        (L("Создайте профиль"),L("Нажмите «Добавить профиль», укажите название, регион и способ входа: через лаунчер или текущий аккаунт CapCut."),"person.crop.circle.badge.plus"),
        (L("Дождитесь подтверждения"),L("Для входа через лаунчер укажите почту и пароль. Для текущего аккаунта сохраните профиль и запустите CapCut: если входа нет, войдите в самом приложении, например через Google. Регион применяется сразу."),"checkmark.shield"),
        (L("Выберите регион"),L("Выберите US, TR, NL или введите другой двухбуквенный код страны. Регион влияет на доступность ресурсов, но не меняет язык и IP-адрес."),"globe.europe.africa"),
        (L("Откройте CapCut"),L("Нажмите «Запустить CapCut». Для смены профиля или региона сначала полностью закройте CapCut. Лаунчер оставляйте работающим."),"play.circle")
    ]
    var body: some View {
        VStack(alignment:.leading,spacing:V(18)) {
            VStack(alignment:.leading,spacing:V(12)) {
                Label(L("Первое открытие в macOS"),systemImage:"macwindow.badge.plus").font(.veil(size:14,weight:.semibold))
                Text(L("Перенесите лаунчер в «Программы» и попробуйте открыть его. Если macOS не разрешает запуск, откройте «Системные настройки» → «Конфиденциальность и безопасность» → «Всё равно открыть», затем подтвердите запуск. Кнопка появляется после попытки открыть приложение."))
                    .font(.veil(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.surface()
            VStack(alignment:.leading,spacing:V(12)) {
                Label(L("Разрешения macOS"),systemImage:"lock.shield").font(.veil(size:14,weight:.semibold))
                Text(L("До запуска CapCut откройте «Системные настройки» → «Конфиденциальность и безопасность» → «Управление приложениями» и включите CapCut Launcher. Если его нет в списке, нажмите «+» и выберите лаунчер в «Программах». После выдачи доступа полностью закройте CapCut и лаунчер, затем откройте их снова."))
                    .font(.veil(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                HStack(spacing:V(12)) {
                    Button {
                        if let url = Bundle.main.resourceURL?.appendingPathComponent("Installer/Installation.pdf") { NSWorkspace.shared.open(url) }
                    } label: { Label(L("Инструкция с иллюстрациями"),systemImage:"doc.richtext") }
                    Button {
                        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security") { NSWorkspace.shared.open(url) }
                    } label: { Label(L("Настройки конфиденциальности"),systemImage:"gearshape") }
                }.buttonStyle(VeilButtonStyle())
            }.surface()
            VStack(alignment:.leading,spacing:V(22)) {
                ForEach(Array(steps.enumerated()),id:\.offset) { index,step in
                    HStack(alignment:.top,spacing:V(15)) {
                        Image(systemName:step.2).font(.veil(size:17)).foregroundStyle(Color.accentColor)
                            .frame(width:V(34),height:V(34)).background(Color.accentColor.opacity(0.08),in:RoundedRectangle(cornerRadius:10))
                        VStack(alignment:.leading,spacing:V(6)) {
                            Text("\(index+1). \(L(step.0))").font(.veil(size:13,weight:.semibold))
                            Text(L(step.1)).font(.veil(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        }
                    }
                }
            }.surface()
            VStack(alignment:.leading,spacing:V(15)) {
                Label(L("Если сессия истекла"),systemImage:"arrow.clockwise.circle").font(.veil(size:14,weight:.semibold))
                Text(L("При истечении сессии лаунчер повторит вход автоматически, если в профиле сохранён пароль. Если CapCut открыт, сначала закройте его. При ошибке проверьте данные в настройках профиля или выберите «Войти через браузер». Ошибка сети сама по себе не означает, что сессия истекла."))
                    .font(.veil(size:12)).foregroundStyle(.secondary)
                Divider()
                Label(L("Профили и проекты"),systemImage:"folder.badge.person.crop").font(.veil(size:14,weight:.semibold))
                Text(L("У профилей лаунчера отдельные браузерные сеансы. Профили «Текущий аккаунт CapCut» используют один официальный вход. После закрытия профиля лаунчера исходный вход CapCut восстанавливается. Локальные проекты остаются общими, удаление профиля их не удаляет."))
                    .font(.veil(size:12)).foregroundStyle(.secondary)
                Text(L("Нажмите карандаш у профиля, чтобы изменить регион и настройки входа. Круглая стрелка проверяет сессию, красная корзина удаляет профиль."))
                    .font(.veil(size:12)).foregroundStyle(.secondary)
                Button { model.openProjects() } label: { Label(L("Открыть папку проектов"),systemImage:"folder") }.buttonStyle(VeilButtonStyle())
            }.surface()
            VStack(alignment:.leading,spacing:V(12)) {
                Label(L("Управление проектами"),systemImage:"film.stack").font(.veil(size:14,weight:.semibold))
                Text(L("В разделе «Проекты» доступны обложки, импорт, экспорт, перенос и удаление выбранных или всех проектов. Для операций полностью закройте CapCut. Удалённые проекты сохраняются в корзине лаунчера и восстанавливаются кнопкой «Восстановить». Очистка отправляет их в системную Корзину macOS. В экспорте выберите «Со всеми материалами», чтобы собрать исходники и обновить связи, или «Только проект», чтобы оставить прежние пути."))
                    .font(.veil(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.surface()
            Text(L("Pro-интерфейс включён при каждом запуске. Подписку и разрешение экспорта проверяет CapCut. Лаунчер — независимое приложение."))
                .font(.veil(size:11)).foregroundStyle(.secondary).padding(.horizontal,V(4))
        }
    }
}

struct UpdatesButton: View {
    @ObservedObject private var interface = InterfacePreferences.shared
    @Environment(\.veil) private var palette
    @ObservedObject var updates: UpdateCenter
    let version: String
    @ViewState var visible = false
    var body: some View {
        Button { visible.toggle() } label: {
            Image(systemName:"arrow.down").font(.veil(size:15,weight:.medium)).frame(width:V(32),height:V(32))
                .foregroundStyle(palette.accent).overlay(Circle().strokeBorder(palette.border,lineWidth:1))
                .overlay(alignment:.topTrailing) {
                    if updates.availableVersion != nil {
                        Text("1").font(.veil(size:8,weight:.bold)).foregroundStyle(.white).frame(width:V(14),height:V(14)).background(palette.accent,in:Circle()).offset(x:3,y:-3)
                    }
                }
        }.buttonStyle(.plain).help(updates.availableVersion == nil ? L("Обновления приложения") : L("Доступно обновление"))
            .accessibilityLabel(updates.availableVersion == nil ? L("Обновления") : L("Доступно 1 обновление"))
            .popover(isPresented:$visible,arrowEdge:.trailing) {
                VStack(alignment:.leading,spacing:V(15)) {
                    Label(L("Обновления"),systemImage:"arrow.down.circle").font(.veil(size:16,weight:.semibold))
                    Text(L("Установлена версия \(version)")).font(.veil(size:11)).foregroundStyle(.secondary)
                    Text(L(updates.message)).font(.veil(size:12)).fixedSize(horizontal:false,vertical:true)
                    if updates.checking { ProgressView().controlSize(.small) }
                    if let newVersion = updates.availableVersion {
                        Button(L("Установить \(newVersion)")) { visible = false; updates.install() }.buttonStyle(VeilButtonStyle(prominent:true))
                    } else if updates.configured {
                        Button(L("Проверить обновления")) { updates.check() }.disabled(updates.checking)
                    }
                }.padding(V(22)).frame(width:V(280)).background(palette.card).veilContext()
            }
    }
}
