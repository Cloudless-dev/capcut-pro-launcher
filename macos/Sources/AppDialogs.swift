import SwiftUI
import Combine
import AppKit

struct AppDialogAction {
    let title: String
    var destructive = false
    var cancel = false
}
struct AppDialog: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var names: [String] = []
    var location: String? = nil
    var symbol = "info.circle"
    let actions: [AppDialogAction]
    let completion: (Int) -> Void
}

/// Application-owned confirmations stay in the launcher window. A queue keeps
/// an incoming notice from replacing an unanswered destructive confirmation.
@MainActor final class AppDialogs: ObservableObject {
    static let shared = AppDialogs()
    @Published private(set) var current: AppDialog?
    private var pending: [AppDialog] = []
    private var keyMonitor: Any?
    private func enqueue(_ dialog: AppDialog) {
        if current == nil { current = dialog } else { pending.append(dialog) }
        if let window = NSApp?.windows.first(where:{$0.title == "CapCut Launcher"}) {
            window.makeKeyAndOrderFront(nil); NSApp?.activate(ignoringOtherApps:true)
        }
        // NSHostingView inside an AppKit window does not always install
        // SwiftUI keyboardShortcut handlers. Handle Escape locally while a
        // dialog is visible; no system-wide event observation is used.
        if keyMonitor == nil, NSApp != nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                let handled = MainActor.assumeIsolated {
                    guard let self, let dialog = self.current,
                          let index = dialog.actions.firstIndex(where:{$0.cancel}) else { return false }
                    self.resolve(index,id:dialog.id)
                    return true
                }
                return handled ? nil : event
            }
        }
    }
    func choose(title: String, message: String, names: [String] = [], location: String? = nil,
                symbol: String = "info.circle", actions: [AppDialogAction]) async -> Int {
        await withCheckedContinuation { continuation in
            enqueue(AppDialog(title:title,message:message,names:names,location:location,symbol:symbol,actions:actions,completion:{continuation.resume(returning:$0)}))
        }
    }
    func notice(_ title: String, _ message: String = "", onClose: @escaping ()->Void = {}) {
        // Repeated Cmd-Q while an operation is running should not stack notices.
        guard current?.title != title || current?.message != message else { return }
        enqueue(AppDialog(title:title,message:message,actions:[AppDialogAction(title:"Понятно",cancel:true)],completion:{_ in onClose()}))
    }
    func resolve(_ index: Int, id: UUID) {
        guard let dialog = current, dialog.id == id, dialog.actions.indices.contains(index) else { return }
        current = pending.isEmpty ? nil : pending.removeFirst()
        if current == nil, let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
        dialog.completion(index)
    }
}

struct LauncherActionStyle: ButtonStyle {
    @ObservedObject private var interface = InterfacePreferences.shared
    @Environment(\.veil) private var palette
    var destructive = false
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let color: Color = destructive ? .red : .accentColor
        configuration.label.font(.veil(size:12,weight:.semibold))
            .padding(.horizontal,V(14)).padding(.vertical,V(10))
            .foregroundStyle(enabled ? (prominent ? destructive ? Color.white : palette.onPrimary : destructive ? Color.red : Color.primary) : Color.secondary)
            .background(enabled && prominent ? color.opacity(configuration.isPressed ? 0.75 : 1) : color.opacity(destructive && enabled ? 0.10 : configuration.isPressed ? 0.12 : 0.055),in:RoundedRectangle(cornerRadius:9))
            .overlay(RoundedRectangle(cornerRadius:9).stroke(color.opacity(destructive && enabled && !prominent ? 0.20 : 0),lineWidth:1))
            .opacity(enabled ? 1 : 0.5)
    }
}

struct AppDialogOverlay: View {
    @ObservedObject private var interface = InterfacePreferences.shared
    @Environment(\.veil) private var palette
    @ObservedObject private var dialogs = AppDialogs.shared
    @FocusState private var cancelFocused: Bool
    var body: some View {
        if let dialog = dialogs.current {
            ZStack {
                Color.black.opacity(0.28).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { }
                VStack(alignment:.leading,spacing:V(18)) {
                    HStack(alignment:.top,spacing:V(13)) {
                        Image(systemName:dialog.symbol).font(.veil(size:23,weight:.medium))
                            .foregroundStyle(dialog.actions.contains(where:{$0.destructive}) ? Color.red : Color.accentColor)
                            .frame(width:V(44),height:V(44)).background(Color.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
                        Text(L(dialog.title)).font(.veil(size:20,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
                            .frame(maxWidth:.infinity,alignment:.leading).padding(.top,V(8))
                    }
                    if !dialog.names.isEmpty {
                        VStack(alignment:.leading,spacing:V(7)) {
                            ForEach(Array(dialog.names.prefix(6).enumerated()),id:\.offset) { _,name in
                                Label(name,systemImage:"film").lineLimit(1).help(name)
                            }
                            if dialog.names.count > 6 {
                                Text(L("…и ещё \(dialog.names.count-6)"))
                                    .foregroundStyle(.secondary).padding(.top,V(3))
                            }
                        }.font(.veil(size:12)).padding(V(13)).frame(maxWidth:.infinity,alignment:.leading)
                            .background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                    }
                    if !dialog.message.isEmpty {
                        Text(L(dialog.message)).font(.veil(size:12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal:false,vertical:true)
                    }
                    if let location = dialog.location {
                        VStack(alignment:.leading,spacing:V(5)) {
                            Text(L("Новое расположение")).font(.veil(size:11,weight:.semibold))
                            Text(location).font(.veil(size:11,design:.monospaced)).foregroundStyle(.secondary)
                                .textSelection(.enabled).fixedSize(horizontal:false,vertical:true).lineLimit(3)
                        }.padding(V(12)).frame(maxWidth:.infinity,alignment:.leading)
                            .background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:9))
                    }
                    HStack(spacing:V(10)) {
                        Spacer(minLength:V(0))
                        ForEach(Array(dialog.actions.enumerated()),id:\.offset) { index,action in
                            if action.cancel {
                                Button(L(action.title)) { dialogs.resolve(index,id:dialog.id) }
                                    .buttonStyle(LauncherActionStyle())
                                    .keyboardShortcut(.cancelAction).focused($cancelFocused)
                            } else {
                                Button(role:action.destructive ? .destructive : nil) { dialogs.resolve(index,id:dialog.id) } label: { Text(L(action.title)) }
                                    .buttonStyle(LauncherActionStyle(destructive:action.destructive,prominent:true))
                            }
                        }
                    }.padding(.top,V(4))
                }.padding(V(26)).frame(maxWidth:530)
                    .background(palette.card,in:RoundedRectangle(cornerRadius:20))
                    .overlay(RoundedRectangle(cornerRadius:20).stroke(Color.primary.opacity(0.09)))
                    .shadow(color:.black.opacity(0.18),radius:30,y:12)
                    .padding(V(24)).id(dialog.id)
                    .onAppear { cancelFocused = true }
                    .accessibilityElement(children:.contain)
                    .accessibilityLabel(L(dialog.title))
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
}
