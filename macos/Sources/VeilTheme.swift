import SwiftUI
import AppKit

/// Shared geometry and typography: changing density relays out real controls,
/// rather than scaling a rasterized window or changing its hit targets.
func V(_ value: CGFloat) -> CGFloat { value * InterfacePreferences.shared.interfaceScale }
extension Font {
    static func veil(size:CGFloat,weight:Font.Weight = .regular,design:Font.Design = .default) -> Font {
        .system(size:V(size),weight:weight,design:design)
    }
}
extension Color {
    init(veil hex:UInt32) {
        self.init(red:Double((hex >> 16) & 255)/255,green:Double((hex >> 8) & 255)/255,blue:Double(hex & 255)/255)
    }
}
struct VeilPalette {
    let light:Bool
    let black:Bool
    init(theme:String,dark:Bool) { light = theme == "light" || theme == "system" && !dark; black = !light && theme != "gray" }
    var canvas:Color { Color(veil:light ? 0xF4F2FC : black ? 0x050506 : 0x232330) }
    var sidebar:Color { Color(veil:light ? 0xEBE7F9 : black ? 0x09090C : 0x2A293A) }
    var card:Color { Color(veil:light ? 0xFFFFFF : black ? 0x141318 : 0x353445) }
    var accent:Color { Color(veil:light ? 0x7250D5 : 0xB99AF5) }
    var accentTop:Color { Color(veil:light ? 0x9879EA : 0xCEB8FF) }
    var primaryButton:Color { light ? Color(veil:0x28273E) : accent }
    var onPrimary:Color { light ? .white : Color(veil:0x1C122E) }
    var border:Color { Color(veil:light ? 0xC4B7EA : black ? 0x514063 : 0x77708E).opacity(light ? 0.42 : 0.38) }
    var highlight:Color { Color.white.opacity(light ? 0.8 : black ? 0.045 : 0.065) }
}
private struct VeilPaletteKey:EnvironmentKey { static let defaultValue = VeilPalette(theme:"light",dark:false) }
extension EnvironmentValues {
    var veil:VeilPalette { get { self[VeilPaletteKey.self] } set { self[VeilPaletteKey.self] = newValue } }
}
/// Applied at each hosting boundary (window, AppKit scroll document and sheet).
struct VeilContext:ViewModifier {
    @ObservedObject private var interface = InterfacePreferences.shared
    @Environment(\.colorScheme) private var scheme
    func body(content:Content) -> some View {
        let palette = VeilPalette(theme:interface.theme,dark:scheme == .dark)
        content.environment(\.veil,palette).environment(\.locale,interface.locale)
            .font(.veil(size:13)).tint(palette.accent).accentColor(palette.accent).buttonStyle(VeilButtonStyle())
            .controlSize(interface.interfaceSize == "small" ? .small : interface.interfaceSize == "large" ? .large : .regular)
    }
}
struct VeilSurface:ViewModifier {
    @ObservedObject private var interface = InterfacePreferences.shared
    @Environment(\.veil) private var palette
    var padding:CGFloat = 20
    var selected = false
    func body(content:Content) -> some View {
        content.padding(V(padding))
            .background(LinearGradient(colors:[palette.card.opacity(palette.light ? 0.90 : 1),palette.card.opacity(palette.light ? 0.54 : 0.74)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:V(18)))
            .overlay(RoundedRectangle(cornerRadius:V(18)).strokeBorder(
                LinearGradient(colors:[selected ? palette.accent.opacity(0.70) : palette.highlight,palette.border.opacity(selected ? 1 : 0.5)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1))
    }
}
extension View {
    func veilContext() -> some View { modifier(VeilContext()) }
    func surface(padding:CGFloat = 20,selected:Bool = false) -> some View { modifier(VeilSurface(padding:padding,selected:selected)) }
}
struct VeilButtonStyle:ButtonStyle {
    @ObservedObject private var interface = InterfacePreferences.shared
    var prominent = false
    @Environment(\.veil) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.veil(size:12,weight:.semibold))
            .padding(.horizontal,V(15)).padding(.vertical,V(11))
            .foregroundStyle(prominent ? palette.onPrimary : Color.primary)
            .background(prominent ? palette.primaryButton : palette.card.opacity(0.5),in:RoundedRectangle(cornerRadius:V(13)))
            .overlay(RoundedRectangle(cornerRadius:V(13)).strokeBorder(palette.border,lineWidth:1))
            .opacity(enabled ? configuration.isPressed ? 0.74 : 1 : 0.4)
            .animation(reduceMotion ? nil : .easeOut(duration:0.12),value:configuration.isPressed)
    }
}
struct VeilIconStyle:ButtonStyle {
    @ObservedObject private var interface = InterfacePreferences.shared
    var destructive = false
    @Environment(\.veil) private var palette
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.veil(size:15,weight:.medium)).frame(width:V(32),height:V(34))
            .foregroundStyle(destructive ? Color.red : Color.primary.opacity(0.85))
            .background(configuration.isPressed ? palette.accent.opacity(0.14) : Color.clear,in:RoundedRectangle(cornerRadius:V(9)))
            .contentShape(RoundedRectangle(cornerRadius:V(9))).opacity(enabled ? 1 : 0.35)
    }
}
