import Foundation
import Combine
import AppKit

/// Preferences are separate from profiles, so older profile documents remain readable.
final class InterfacePreferences: ObservableObject {
    static let shared = InterfacePreferences()
    static let changed = Notification.Name("LauncherInterfaceChanged")
    private let defaults: UserDefaults
    @Published var language: String { didSet { defaults.set(language,forKey:"interfaceLanguage"); apply() } }
    @Published var theme: String { didSet { defaults.set(theme,forKey:"interfaceTheme"); apply() } }
    var effectiveLanguage: String { Self.resolve(language,preferred:Locale.preferredLanguages) }
    var locale: Locale { Locale(identifier:effectiveLanguage) }
    init(defaults:UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey:"interfaceLanguage") ?? "system"
        language = ["system","ru","en"].contains(saved) ? saved : "system"
        let appearance = defaults.string(forKey:"interfaceTheme") ?? "system"
        theme = ["system","light","dark"].contains(appearance) ? appearance : "system"
    }
    static func resolve(_ selection:String,preferred:[String]) -> String {
        if ["ru","en"].contains(selection) { return selection }
        for item in preferred {
            let code = item.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
            if ["ru","en"].contains(code) { return code }
        }
        return "en"
    }
    func apply() {
        NSApp?.appearance = theme == "light" ? NSAppearance(named:.aqua) : theme == "dark" ? NSAppearance(named:.darkAqua) : nil
        NotificationCenter.default.post(name:Self.changed,object:nil)
    }
}

/// Loaded once. Dynamic helper messages use the same catalog as interface labels.
struct TranslationCatalog {
    let entries: [String:String]
    private let patterns: [(NSRegularExpression,[String])]
    init(entries:[String:String]) {
        self.entries = entries
        patterns = entries.sorted { $0.key.count > $1.key.count }.compactMap { key,value in
            let parts = key.components(separatedBy:"%@")
            guard parts.count > 1 else { return nil }
            let pattern = "^" + parts.map(NSRegularExpression.escapedPattern(for:)).joined(separator:"(.*?)") + "$"
            guard let regex = try? NSRegularExpression(pattern:pattern,options:[.dotMatchesLineSeparators]) else { return nil }
            return (regex,value.components(separatedBy:"%@"))
        }
    }
    func translate(_ text:String,language:String) -> String {
        guard language == "en" else { return text }
        if let value = entries[text] { return value }
        let ns = text as NSString
        for (regex,parts) in patterns {
            guard let match = regex.firstMatch(in:text,range:NSRange(location:0,length:ns.length)),parts.count == match.numberOfRanges else { continue }
            var output = parts[0]
            for index in 1..<parts.count { output += ns.substring(with:match.range(at:index)) + parts[index] }
            return output
        }
        return text
    }
    static let bundled: TranslationCatalog = {
        guard let url = Bundle.main.url(forResource:"Localizable",withExtension:"strings",subdirectory:"en.lproj"),
              let data = try? Data(contentsOf:url),
              let entries = try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:String] else { return TranslationCatalog(entries:[:]) }
        return TranslationCatalog(entries:entries)
    }()
}
func L(_ text:String) -> String { TranslationCatalog.bundled.translate(text,language:InterfacePreferences.shared.effectiveLanguage) }
