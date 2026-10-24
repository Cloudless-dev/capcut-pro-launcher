import AppKit
import SwiftUI

@MainActor
final class LauncherApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var model: LauncherModel!
    func applicationDidFinishLaunching(_ notification:Notification) {

        NSApp.setActivationPolicy(.regular)
        do { model = try LauncherModel() }
        catch { showStartupError(error); return }
        InterfacePreferences.shared.apply()
        NotificationCenter.default.addObserver(self,selector:#selector(interfaceChanged),name:InterfacePreferences.changed,object:nil)
        setupMenu()
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1080,height:760),styleMask:[.titled,.closable,.resizable,.miniaturizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.title = "CapCut Launcher"; window.minSize = NSSize(width:820,height:650)
        window.isReleasedWhenClosed = false; window.delegate = self
        let content = NSHostingView(rootView:LauncherRootView(model:model))
        // The window owns its size. Avoid three SwiftUI min/ideal/max measurement
        // passes on every page change; content remains flexible inside these bounds.
        content.sizingOptions = []
        content.frame = window.contentLayoutRect
        content.autoresizingMask = [.width,.height]
        window.contentView = content
        window.contentMinSize = NSSize(width:820,height:650)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    private func showStartupError(_ error:Error) {
        InterfacePreferences.shared.apply()
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:430),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title = "CapCut Launcher"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:AppDialogOverlay().background(Color(nsColor:.windowBackgroundColor)))
        AppDialogs.shared.notice("Не удалось открыть профили",error.localizedDescription) { NSApp.terminate(nil) }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc func interfaceChanged() { setupMenu() }
    func setupMenu() {
        let main = NSMenu(); let appItem = NSMenuItem(); main.addItem(appItem); let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle:L("О CapCut Launcher"),action:#selector(about),keyEquivalent:"")
        appMenu.addItem(withTitle:L("Настройки…"),action:#selector(settings),keyEquivalent:",")
        appMenu.addItem(withTitle:L("Инструкция"),action:#selector(guide),keyEquivalent:"?")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle:L("Показать окно"),action:#selector(showWindow),keyEquivalent:"0")
        appMenu.addItem(withTitle:L("Выйти"),action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let editItem = NSMenuItem(); main.addItem(editItem); let edit = NSMenu(title:L("Правка")); editItem.submenu = edit
        for (title,selector,key) in [(L("Вырезать"),#selector(NSText.cut(_:)),"x"),(L("Копировать"),#selector(NSText.copy(_:)),"c"),(L("Вставить"),#selector(NSText.paste(_:)),"v"),(L("Выделить всё"),#selector(NSText.selectAll(_:)),"a")] { edit.addItem(withTitle:L(title),action:selector,keyEquivalent:key) }
        NSApp.mainMenu = main
    }
    @objc func settings() { model.destination = "settings"; showWindow() }
    @objc func guide() { model.destination = "guide"; showWindow() }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    @objc func about() { showWindow(); AppDialogs.shared.notice("CapCut Launcher \(model.version)","Профили, вход через браузер и выбор региона.\nНезависимый лаунчер для официального CapCut.") }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.projects.working {
            showWindow(); AppDialogs.shared.notice("Дождитесь завершения операции с проектами."); return .terminateCancel
        }
        if model.helper?.isRunning == true {
            showWindow(); AppDialogs.shared.notice("Сначала закройте CapCut","Лаунчер сопровождает текущий запуск. После закрытия CapCut можно выйти."); return .terminateCancel
        }
        model.checks.values.forEach{$0.terminate()}; return .terminateNow
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool { showWindow(); return true }
}

// Exercise dyld and the packaged resources without accessing account data.
// This runs from the final signed bundle as part of every release build.
if CommandLine.arguments.contains("--check") {
    guard let resources = Bundle.main.resourceURL,
        FileManager.default.fileExists(atPath:resources.appendingPathComponent("Browser/CapCut Login.app/Contents/MacOS/CapCutLogin").path),
        TranslationCatalog.bundled.translate("Настройки",language:"en") == "Settings" else {
        fputs("Bundle resource check failed\n",stderr); exit(1)
    }
    print("Launcher startup check passed (Sparkle loaded)")
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = LauncherApp()
    app.delegate = delegate
    app.run()
}
