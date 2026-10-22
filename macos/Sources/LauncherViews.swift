import SwiftUI
import AppKit

// Explicit type alias keeps the stable property-wrapper API on SDKs that also expose a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

private extension View {
    func surface() -> some View {
        self.padding(20).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).stroke(Color.primary.opacity(0.07),lineWidth:1))
    }
}

struct LauncherRootView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject private var interface = InterfacePreferences.shared
    var body: some View {
        HStack(spacing:0) {
            sidebar.frame(width:190)
            Divider()
            VStack(spacing:0) {
                header
                Divider().opacity(0.6)
                PageScrollView(page:model.destination) {
                    Group {
                        switch model.destination {
                        case "guide": GuidePage(model:model)
                        case "settings": SettingsPage(model:model)
                        default: ProfilesPage(model:model)
                        }
                    }.padding(28).frame(maxWidth:1000,alignment:.topLeading).frame(maxWidth:.infinity)
                }.id(interface.effectiveLanguage).frame(maxWidth:.infinity,maxHeight:.infinity)
                if model.destination == "profiles", model.selectedProfile != nil { LaunchBar(model:model) }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }
        .environment(\.locale,interface.locale)
        .background(Color(nsColor:.windowBackgroundColor))
        .sheet(isPresented:$model.profileEditorVisible) { ProfileEditor(model:model) }
        .onAppear { model.checkSelectedSession() }
    }
    var sidebar: some View {
        VStack(alignment:.leading,spacing:24) {
            HStack(spacing:10) {
                Image(nsImage:NSImage(named:NSImage.Name("AppIcon")) ?? NSApp.applicationIconImage).resizable().frame(width:34,height:34)
                VStack(alignment:.leading,spacing:2) {
                    Text("Launcher").font(.system(size:16,weight:.semibold))
                    Text(L("для CapCut")).font(.system(size:11)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal,8).padding(.top,8)
            VStack(spacing:5) {
                navigation("profiles",title:L("Профили"),icon:"person.crop.rectangle.stack")
                navigation("guide",title:L("Инструкция"),icon:"book.closed")
                navigation("settings",title:L("Настройки"),icon:"slider.horizontal.3")
            }
            Spacer()
            if let active = model.runningProfile {
                HStack(spacing:7) {
                    Circle().fill(Color.green).frame(width:6,height:6)
                    VStack(alignment:.leading,spacing:3) {
                        Text(L("CapCut открыт")).font(.system(size:11,weight:.medium))
                        Text(active.name).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
                    .background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
            }
            HStack { Text(L("Версия \(model.version)")); Spacer(); Image(systemName:"macwindow") }
                .font(.system(size:10)).foregroundStyle(.tertiary).padding(.horizontal,8)
        }.padding(16).frame(maxHeight:.infinity).background(Color(nsColor:.underPageBackgroundColor).opacity(0.55))
    }
    func navigation(_ id: String,title: String,icon: String) -> some View {
        Button {

            model.destination = id
        } label: {
            HStack(spacing:10) {
                Image(systemName:icon).font(.system(size:15,weight:.medium)).frame(width:20)
                Text(L(title)).font(.system(size:13,weight:model.destination == id ? .semibold : .regular))
                Spacer()
            }.padding(.horizontal,12).padding(.vertical,11)
                .foregroundStyle(model.destination == id ? Color.accentColor : Color.primary.opacity(0.8))
                .background(model.destination == id ? Color.accentColor.opacity(0.10) : Color.clear,in:RoundedRectangle(cornerRadius:10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    var header: some View {
        HStack(alignment:.center) {
            VStack(alignment:.leading,spacing:5) {
                Text(model.destination == "settings" ? L("Настройки") : model.destination == "guide" ? L("Инструкция") : L("Профили"))
                    .font(.system(size:23,weight:.semibold))
                Text(model.destination == "settings" ? L("Настройте лаунчер под свой привычный сценарий.") : model.destination == "guide" ? L("Вход, смена региона и работа с профилями.") : L("Отдельный вход и регион для каждого аккаунта."))
                    .font(.system(size:12)).foregroundStyle(.secondary)
            }
            Spacer(minLength:20)
            UpdatesButton(updates:model.updates,version:model.version)
        }.padding(.horizontal,28).padding(.vertical,23)
    }
}

struct ProfilesPage: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Text(L("ВАШИ ПРОФИЛИ")).font(.system(size:10,weight:.semibold)).tracking(1).foregroundStyle(.secondary)
                Text("\(model.document.profiles.count)").font(.system(size:10,weight:.medium)).padding(.horizontal,6).padding(.vertical,3)
                    .background(Color.primary.opacity(0.06),in:Capsule())
                Spacer()
                Button { model.addProfile() } label: { Label(L("Добавить профиль"),systemImage:"plus") }.buttonStyle(.bordered)
            }
            if model.document.profiles.isEmpty {
                VStack(spacing:14) {
                    Image(systemName:"person.crop.circle.badge.plus").font(.system(size:36,weight:.light)).foregroundStyle(Color.accentColor)
                    Text(L("Первый профиль")).font(.system(size:19,weight:.semibold))
                    Text(L("Создайте профиль и укажите почту и пароль CapCut.\nЛаунчер выполнит вход и сохранит выбранный регион."))
                        .font(.system(size:13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(L("Создать профиль")) { model.addProfile() }.buttonStyle(.borderedProminent).controlSize(.large)
                }.frame(maxWidth:.infinity).padding(.vertical,60).surface()
            } else {
                VStack(spacing:8) {
                    ForEach(model.document.profiles) { profile in
                        ProfileRow(profile:profile,selected:model.document.selectedProfileID == profile.id,
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
                if let profile = model.selectedProfile { ProfileDetail(model:model,profile:profile).id(profile.id) }
            }
        }
    }
}

struct ProfileRow: View {
    let profile: LauncherProfile
    let selected: Bool
    let running: Bool
    let checking: Bool
    let select: () -> Void
    var body: some View {
        Button(action:select) {
            HStack(spacing:12) {
                Text(String(profile.name.prefix(1)).uppercased()).font(.system(size:16,weight:.semibold))
                    .foregroundStyle(selected ? Color.accentColor : .secondary).frame(width:38,height:38)
                    .background(selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.055),in:RoundedRectangle(cornerRadius:11))
                VStack(alignment:.leading,spacing:4) {
                    HStack(spacing:7) {
                        Text(profile.name).font(.system(size:13,weight:.semibold)).lineLimit(1)
                        if running { Text(L("ОТКРЫТ")).font(.system(size:8,weight:.bold)).foregroundStyle(.green).padding(.horizontal,5).padding(.vertical,2).background(Color.green.opacity(0.10),in:Capsule()) }
                    }
                    Text(profile.accountLabel.isEmpty ? L("Вход ещё не выполнен") : profile.accountLabel).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength:8)
                if checking { ProgressView().controlSize(.small).help(L("Проверяю вход на сервере")) }
                else { AuthBadge(state:profile.authState) }
                Text(profile.region).font(.system(size:11,weight:.medium,design:.monospaced)).foregroundStyle(.secondary)
                    .padding(.horizontal,8).padding(.vertical,5).background(Color.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:6))
                Image(systemName:selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.14)).font(.system(size:17))
            }.padding(13).contentShape(Rectangle())
                .background(selected ? Color.accentColor.opacity(0.035) : Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:13))
                .overlay(RoundedRectangle(cornerRadius:13).stroke(selected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.075),lineWidth:1))
        }.buttonStyle(.plain).accessibilityLabel(L("Профиль \(profile.name), \(L(profile.authState.title)), регион \(profile.region)"))
    }
}

struct AuthBadge: View {
    let state: ProfileAuthState
    var color: Color { state == .valid ? .green : (state == .expired || state == .needsLogin) ? .orange : .secondary }
    var body: some View {
        HStack(spacing:4) {
            Image(systemName:state == .valid ? "checkmark.shield" : state == .expired || state == .needsLogin ? "exclamationmark.circle" : "person.crop.circle")
            Text(L(state.title))
        }.font(.system(size:10,weight:.medium)).foregroundStyle(color).padding(.horizontal,8).padding(.vertical,5)
            .background(color.opacity(0.08),in:Capsule())
    }
}

struct ProfileDetail: View {
    @ObservedObject var model: LauncherModel
    let profile: LauncherProfile
    @ViewState private var regionInput: String
    init(model:LauncherModel,profile:LauncherProfile) { self.model = model; self.profile = profile; _regionInput = ViewState(initialValue:profile.region) }
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                Label(L("Настройки профиля"),systemImage:"person.crop.rectangle").font(.system(size:13,weight:.semibold))
                Spacer()
                Menu {
                    Button(L("Редактировать профиль"),systemImage:"pencil") { model.renameProfile(profile) }.disabled(model.busy)
                    Button(L("Войти через браузер"),systemImage:"safari") { model.signIn(profile.id,manualBrowser:true) }.disabled(model.busy)
                    Button(L("Удалить профиль"),systemImage:"trash",role:.destructive) { model.deleteProfile(profile) }
                        .disabled(model.runningProfileID == profile.id || model.browserProfileID == profile.id)
                } label: { Image(systemName:"ellipsis").frame(width:22,height:20) }.menuStyle(.borderlessButton).fixedSize().help(L("Действия с профилем"))
            }
            HStack(alignment:.top,spacing:18) {
                Image(systemName:"globe.europe.africa").font(.system(size:20)).foregroundStyle(.secondary).frame(width:24).padding(.top,4)
                VStack(alignment:.leading,spacing:9) {
                    HStack {
                        Text(L("Регион")).font(.system(size:13,weight:.medium))
                        Spacer()
                        Text("Pro").font(.system(size:10,weight:.semibold)).foregroundStyle(Color.accentColor).padding(.horizontal,8).padding(.vertical,4)
                            .background(Color.accentColor.opacity(0.08),in:Capsule()).help(L("Запуск с Pro-интерфейсом всегда включён"))
                    }
                    HStack(spacing:8) {
                        CountryCombo(text:$regionInput) { _ = model.setRegion(regionInput,profileID:profile.id) }.frame(width:235,height:28)
                            .disabled(model.runningProfileID == profile.id)
                        if regionInput != profile.region {
                            Button { if model.setRegion(regionInput,profileID:profile.id) { regionInput = profile.region } } label: { Image(systemName:"checkmark") }
                                .help(L("Сохранить регион")).disabled(model.runningProfileID == profile.id)
                        }
                    }
                    Text(L("Или введите код любой страны, например US.")).font(.system(size:11)).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(alignment:.center,spacing:18) {
                Image(systemName:profile.authState == .expired ? "exclamationmark.shield" : "safari").font(.system(size:20)).foregroundStyle(.secondary).frame(width:24)
                VStack(alignment:.leading,spacing:5) {
                    Text(profile.authState == .expired ? L("Сессия истекла") : profile.automaticSignIn == true ? L("Автоматический вход") : L("Вход через браузер")).font(.system(size:13,weight:.medium))
                    Text(model.browserProfileID == profile.id ? L("Выполняю автоматический вход…") : profile.authState == .expired || profile.authState == .needsLogin ? L("Войдите заново, чтобы продолжить работу.") : L("У каждого профиля свой отдельный браузерный сеанс."))
                        .font(.system(size:11)).foregroundStyle(.secondary)
                }
                Spacer(minLength:10)
                if profile.authState != .signedOut {
                    Button { model.verifySession(profile.id) } label: { Image(systemName:"arrow.clockwise") }
                        .buttonStyle(.borderless).help(L("Проверить сессию")).disabled(model.checkingProfiles.contains(profile.id) || model.busy)
                }
                if model.browserProfileID == profile.id {
                    Button(L("Отменить вход")) { model.cancelSignIn(profile.id) }.buttonStyle(.bordered)
                } else {
                    Button(profile.authState == .signedOut ? L("Войти") : profile.authState == .expired || profile.authState == .needsLogin ? L("Войти заново") : L("Повторный вход")) { model.signIn(profile.id) }
                        .buttonStyle(.bordered).disabled(model.busy)
                }
            }
        }.surface()
    }
}

struct CountryCombo: NSViewRepresentable {
    @Binding var text: String
    var commit: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context:Context) -> NSComboBox {
        let combo = NSComboBox(); combo.isEditable = true; combo.completes = false; combo.delegate = context.coordinator
        combo.addItems(withObjectValues:[L("US — США"),L("TR — Турция"),L("NL — Нидерланды"),L("GB — Великобритания"),L("DE — Германия"),L("FR — Франция"),L("SG — Сингапур"),L("CA — Канада"),L("AU — Австралия"),L("JP — Япония"),L("KR — Южная Корея"),L("BR — Бразилия"),L("RU — Россия")])
        combo.setAccessibilityLabel(L("Регион профиля")); combo.font = .systemFont(ofSize:13); return combo
    }
    func updateNSView(_ combo:NSComboBox,context:Context) { context.coordinator.parent = self; if combo.stringValue != text { combo.stringValue = text } }
    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: CountryCombo
        init(_ parent:CountryCombo) { self.parent = parent }
        func controlTextDidChange(_ notification:Notification) { if let combo = notification.object as? NSComboBox { parent.text = combo.stringValue } }
        func controlTextDidEndEditing(_ notification:Notification) { if let combo = notification.object as? NSComboBox { parent.text = combo.stringValue; parent.commit() } }
        func comboBoxSelectionDidChange(_ notification:Notification) {
            if let combo = notification.object as? NSComboBox, let value = combo.objectValueOfSelectedItem as? String {
                parent.text = value; DispatchQueue.main.async { self.parent.commit() }
            }
        }
    }
}

struct LaunchBar: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(spacing:0) {
            Divider()
            HStack(spacing:18) {
                VStack(alignment:.leading,spacing:7) {
                    HStack(spacing:7) {
                        if model.launching { ProgressView().controlSize(.mini) }
                        else { Image(systemName:model.statusIsError ? "exclamationmark.circle" : model.runningProfileID != nil ? "checkmark.circle.fill" : "circle.fill")
                            .font(.system(size:model.runningProfileID == nil && !model.statusIsError ? 6 : 12)).foregroundStyle(model.statusIsError ? Color.orange : model.runningProfileID != nil ? Color.green : Color.secondary) }
                        Text(L(model.status)).font(.system(size:11,weight:.medium)).lineLimit(2)
                    }
                    if let profile = model.selectedProfile {
                        HStack(spacing:12) {
                            Text(L("Регион: \(model.runningProfileID == profile.id && !model.observedRegion.isEmpty ? model.observedRegion : profile.region)"))
                            if model.runningProfileID == profile.id { Text(model.nativeVerified ? L("Вход подтверждён") : L("Проверяю вход в CapCut…")) }
                        }.font(.system(size:10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength:5)
                if let profile = model.selectedProfile {
                    Button { model.startCapCut(profile.id) } label: {
                        Label(model.launching ? L("Запускаю…") : model.runningProfileID == profile.id ? L("Показать CapCut") : L("Запустить CapCut"),
                            systemImage:model.runningProfileID == profile.id ? "arrow.up.right.square" : "play.fill")
                        .font(.system(size:13,weight:.semibold)).padding(.horizontal,10).padding(.vertical,5)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.launching || model.browser != nil || model.runningProfileID != nil && model.runningProfileID != profile.id || model.runningProfileID == nil && (profile.authState != .valid || model.checkingProfiles.contains(profile.id)))
                }
            }.padding(.horizontal,28).padding(.vertical,20)
        }.background(Color(nsColor:.controlBackgroundColor).opacity(0.55))
    }
}

struct ProfileEditor: View {
    @ObservedObject var model: LauncherModel
    @FocusState var focused: Bool
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Label(model.editingProfileID == nil ? L("Новый профиль") : L("Редактировать профиль"),systemImage:model.editingProfileID == nil ? "person.crop.circle.badge.plus" : "pencil")
                .font(.system(size:19,weight:.semibold))
            TextField(L("Название профиля"),text:$model.profileNameDraft).textFieldStyle(.roundedBorder).focused($focused).onSubmit { model.saveProfileName() }
            Toggle(L("Автоматический вход"),isOn:$model.profileAutomaticDraft).toggleStyle(.switch)
            if model.profileAutomaticDraft {
                TextField(L("Почта CapCut"),text:$model.profileEmailDraft).textFieldStyle(.roundedBorder)
                SecureField(model.profileHasPassword ? L("Новый пароль (необязательно)") : L("Пароль CapCut"),text:$model.profilePasswordDraft).textFieldStyle(.roundedBorder)
                Label(L("Пароль сохраняется в Связке ключей этого Mac. Вход выполняется на сайте CapCut в фоне."),systemImage:"lock.shield")
                    .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            } else {
                Text(L("Вход выполняется через окно комплектного браузера.")).font(.system(size:12)).foregroundStyle(.secondary)
            }
            if !model.editorError.isEmpty { Text(L(model.editorError)).font(.system(size:11)).foregroundStyle(.orange) }
            HStack { Spacer(); Button(L("Отмена")) { model.dismissProfileEditor() }.keyboardShortcut(.cancelAction)
                Button(model.editorNeedsSignIn ? L("Сохранить и войти") : L("Сохранить")) { model.saveProfileName() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(model.profileNameDraft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.profileAutomaticDraft && (model.profileEmailDraft.isEmpty || model.profilePasswordDraft.isEmpty && !model.profileHasPassword)) }
        }.padding(28).frame(width:430).onAppear { focused = true }.onDisappear { model.profilePasswordDraft = "" }
    }
}

struct SettingsPage: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject private var interface = InterfacePreferences.shared
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            VStack(alignment:.leading,spacing:18) {
                Label(L("Оформление"),systemImage:"paintpalette").font(.system(size:14,weight:.semibold))
                HStack {
                    Text(L("Язык интерфейса")); Spacer()
                    Picker(L("Язык интерфейса"),selection:$interface.language) {
                        Text(L("Системный")).tag("system")
                        Text("Русский").tag("ru")
                        Text("English").tag("en")
                    }.labelsHidden().frame(width:180)
                }
                Divider()
                HStack {
                    Text(L("Тема")); Spacer()
                    Picker(L("Тема"),selection:$interface.theme) {
                        Text(L("Системная")).tag("system")
                        Text(L("Светлая")).tag("light")
                        Text(L("Тёмная")).tag("dark")
                    }.labelsHidden().frame(width:180)
                }
                Text(L("По умолчанию язык и тема соответствуют настройкам macOS.")).font(.system(size:11)).foregroundStyle(.secondary)
            }.surface()
            VStack(alignment:.leading,spacing:20) {
                Label(L("Поведение лаунчера"),systemImage:"switch.2").font(.system(size:14,weight:.semibold))
                settingToggle(L("Запуск после авторизации"),
                    description:L("Автоматически открывать CapCut после успешного входа в браузере."),
                    value:Binding(get:{model.document.settings.autoStartAfterAuth},set:model.setAutoStart))
                Divider()
                settingToggle(L("Автообновления"),
                    description:L("Проверять и загружать новые версии автоматически."),
                    value:Binding(get:{model.document.settings.automaticUpdates},set:model.setAutomaticUpdates))
                if !model.updates.configured { Text(L("В этой локальной сборке обновления пока не опубликованы. Настройка сохранится для будущих версий.")).font(.system(size:11)).foregroundStyle(.secondary) }
            }.surface()
            VStack(alignment:.leading,spacing:18) {
                Label(L("Расположение файлов"),systemImage:"folder").font(.system(size:14,weight:.semibold))
                pathRow(L("Приложение CapCut"),path:model.document.settings.appPath,choose:model.chooseApp)
                Divider()
                pathRow(L("Данные CapCut"),path:model.document.settings.dataRoot,choose:model.chooseData)
                Button { model.openProjects() } label: { Label(L("Открыть локальные проекты"),systemImage:"folder.badge.gearshape") }.buttonStyle(.bordered)
            }.surface()
            HStack(alignment:.top,spacing:12) {
                Image(systemName:"lock.shield").font(.system(size:18)).foregroundStyle(.secondary)
                Text(L("Входы хранятся в Keychain macOS. Браузерные данные разделены по профилям. Локальные проекты CapCut остаются общими."))
                    .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(.horizontal,4)
        }
    }
    func settingToggle(_ title:String,description:String,value:Binding<Bool>) -> some View {
        HStack(alignment:.center,spacing:24) {
            VStack(alignment:.leading,spacing:5) {
                Text(L(title)).font(.system(size:13,weight:.medium))
                Text(L(description)).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading)
            Toggle(title,isOn:value).labelsHidden().toggleStyle(.switch)
                .fixedSize().accessibilityLabel(L(title)).accessibilityHint(L(description))
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    func pathRow(_ title:String,path:String,choose:@escaping ()->Void) -> some View {
        HStack(spacing:15) {
            VStack(alignment:.leading,spacing:6) {
                Text(L(title)).font(.system(size:12,weight:.medium))
                Text(path).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer(minLength:10)
            Button(L("Выбрать…"),action:choose).disabled(model.busy)
        }
    }
}

struct GuidePage: View {
    let model: LauncherModel
    let steps = [
        (L("Создайте профиль"),L("Нажмите «Добавить профиль», укажите название, почту и пароль CapCut, затем «Сохранить и войти»."),"person.crop.circle.badge.plus"),
        (L("Дождитесь подтверждения"),L("Лаунчер входит через комплектный браузер в фоне. После проверки сервером появится «Вход подтверждён», и кнопка запуска станет доступна. При необходимости CapCut откроет окно подтверждения."),"checkmark.shield"),
        (L("Выберите регион"),L("Выберите US, TR, NL или введите другой двухбуквенный код страны. Регион влияет на доступность ресурсов, но не меняет язык и IP-адрес."),"globe.europe.africa"),
        (L("Откройте CapCut"),L("Нажмите «Запустить CapCut». Для смены профиля или региона сначала полностью закройте CapCut. Лаунчер оставляйте работающим."),"play.circle")
    ]
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            VStack(alignment:.leading,spacing:12) {
                Label(L("Первое открытие в macOS"),systemImage:"macwindow.badge.plus").font(.system(size:14,weight:.semibold))
                Text(L("Перенесите лаунчер в «Программы» и попробуйте открыть его. Если macOS не разрешает запуск, откройте «Системные настройки» → «Конфиденциальность и безопасность» → «Всё равно открыть», затем подтвердите запуск. Кнопка появляется после попытки открыть приложение."))
                    .font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.surface()
            VStack(alignment:.leading,spacing:12) {
                Label(L("Разрешения macOS"),systemImage:"lock.shield").font(.system(size:14,weight:.semibold))
                Text(L("До запуска CapCut откройте «Системные настройки» → «Конфиденциальность и безопасность» → «Управление приложениями» и включите CapCut Launcher. Если его нет в списке, нажмите «+» и выберите лаунчер в «Программах». После выдачи доступа полностью закройте CapCut и лаунчер, затем откройте их снова."))
                    .font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                HStack(spacing:12) {
                    Button {
                        if let url = Bundle.main.resourceURL?.appendingPathComponent("Installer/Installation.pdf") { NSWorkspace.shared.open(url) }
                    } label: { Label(L("Инструкция с иллюстрациями"),systemImage:"doc.richtext") }
                    Button {
                        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security") { NSWorkspace.shared.open(url) }
                    } label: { Label(L("Настройки конфиденциальности"),systemImage:"gearshape") }
                }.buttonStyle(.bordered)
            }.surface()
            VStack(alignment:.leading,spacing:22) {
                ForEach(Array(steps.enumerated()),id:\.offset) { index,step in
                    HStack(alignment:.top,spacing:15) {
                        Image(systemName:step.2).font(.system(size:17)).foregroundStyle(Color.accentColor)
                            .frame(width:34,height:34).background(Color.accentColor.opacity(0.08),in:RoundedRectangle(cornerRadius:10))
                        VStack(alignment:.leading,spacing:6) {
                            Text("\(index+1). \(L(step.0))").font(.system(size:13,weight:.semibold))
                            Text(L(step.1)).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        }
                    }
                }
            }.surface()
            VStack(alignment:.leading,spacing:15) {
                Label(L("Если сессия истекла"),systemImage:"arrow.clockwise.circle").font(.system(size:14,weight:.semibold))
                Text(L("При истечении сессии лаунчер повторит вход автоматически, если в профиле сохранён пароль. Если CapCut открыт, сначала закройте его. При ошибке проверьте данные в настройках профиля или выберите «Войти через браузер». Ошибка сети сама по себе не означает, что сессия истекла."))
                    .font(.system(size:12)).foregroundStyle(.secondary)
                Divider()
                Label(L("Профили и проекты"),systemImage:"folder.badge.person.crop").font(.system(size:14,weight:.semibold))
                Text(L("Профили разделяют аккаунты и браузерные сеансы. Локальные проекты CapCut остаются общими. Удаление профиля лаунчера не удаляет проекты. Перед обновлением самого CapCut сохраняйте отдельную резервную копию проектов и исходного медиа."))
                    .font(.system(size:12)).foregroundStyle(.secondary)
                Button { model.openProjects() } label: { Label(L("Открыть папку проектов"),systemImage:"folder") }.buttonStyle(.bordered)
            }.surface()
            Text(L("Pro-интерфейс включён при каждом запуске. Подписку и разрешение экспорта проверяет CapCut. Лаунчер — независимое приложение."))
                .font(.system(size:11)).foregroundStyle(.secondary).padding(.horizontal,4)
        }
    }
}

struct UpdatesButton: View {
    @ObservedObject var updates: UpdateCenter
    let version: String
    @ViewState var visible = false
    var body: some View {
        Button { visible.toggle() } label: {
            Image(systemName:"arrow.down.circle").font(.system(size:21,weight:.regular)).foregroundStyle(.secondary).frame(width:34,height:34)
                .background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                .overlay(alignment:.topTrailing) {
                    if updates.availableVersion != nil {
                        Text("1").font(.system(size:8,weight:.bold)).foregroundStyle(.white).frame(width:14,height:14).background(Color.red,in:Circle()).offset(x:3,y:-3)
                    }
                }
        }.buttonStyle(.plain).help(updates.availableVersion == nil ? L("Обновления приложения") : L("Доступно обновление"))
            .accessibilityLabel(updates.availableVersion == nil ? L("Обновления") : L("Доступно 1 обновление"))
            .popover(isPresented:$visible,arrowEdge:.bottom) {
                VStack(alignment:.leading,spacing:15) {
                    Label(L("Обновления"),systemImage:"arrow.down.circle").font(.system(size:16,weight:.semibold))
                    Text(L("Установлена версия \(version)")).font(.system(size:11)).foregroundStyle(.secondary)
                    Text(L(updates.message)).font(.system(size:12)).fixedSize(horizontal:false,vertical:true)
                    if updates.checking { ProgressView().controlSize(.small) }
                    if let newVersion = updates.availableVersion {
                        Button(L("Установить \(newVersion)")) { visible = false; updates.install() }.buttonStyle(.borderedProminent)
                    } else if updates.configured {
                        Button(L("Проверить обновления")) { updates.check() }.disabled(updates.checking)
                    }
                }.padding(22).frame(width:280)
            }
    }
}
