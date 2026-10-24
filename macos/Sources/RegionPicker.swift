import SwiftUI

/// One selector for the profile card and its editor. Its binding always stores
/// the ISO code, never the decorated title shown by the menu.
struct RegionPicker:View {
    @Binding var code:String
    @ObservedObject private var interface = InterfacePreferences.shared
    @ViewState private var customVisible = false
    @ViewState private var customCode = ""
    @ViewState private var error = ""
    static let common = ["US","TR","NL","GB","DE","FR","SG","CA","AU","JP","KR","BR","RU"]
    var body:some View {
        Menu {
            ForEach(Self.common,id:\.self) { country in
                Button { code = country } label: {
                    if country == code { Label(Self.title(country),systemImage:"checkmark") }
                    else { Text(Self.title(country)) }
                }
            }
            Divider()
            Button(L("Другой регион…")) { customCode = code; error = ""; customVisible = true }
        } label: { Text(Self.title(code)).font(.veil(size:11,weight:.medium)) }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel(L("Регион профиля")+" "+code)
            .popover(isPresented:$customVisible) {
                VStack(alignment:.leading,spacing:V(12)) {
                    Text(L("Регион профиля")).font(.veil(size:15,weight:.semibold))
                    TextField(L("Код страны"),text:$customCode).textFieldStyle(.roundedBorder).onSubmit(apply)
                    Text(L("Или введите код любой страны, например US.")).font(.veil(size:11)).foregroundStyle(.secondary)
                    if !error.isEmpty { Text(L(error)).font(.veil(size:11)).foregroundStyle(.orange) }
                    HStack {
                        Button(L("Отмена")) { customVisible = false }
                        Spacer()
                        Button(L("Применить"),action:apply).buttonStyle(VeilButtonStyle(prominent:true))
                    }
                }.padding(V(20)).frame(width:V(280)).veilContext()
            }
    }
    private func apply() {
        do { code = try ProfileStore.countryCode(customCode); customVisible = false }
        catch { self.error = error.localizedDescription }
    }
    static func title(_ code:String)->String {
        let names = ["US":"US — США","TR":"TR — Турция","NL":"NL — Нидерланды","GB":"GB — Великобритания","DE":"DE — Германия","FR":"FR — Франция","SG":"SG — Сингапур","CA":"CA — Канада","AU":"AU — Австралия","JP":"JP — Япония","KR":"KR — Южная Корея","BR":"BR — Бразилия","RU":"RU — Россия"]
        return flag(code)+"  "+(names[code].map(L) ?? code)
    }
    static func flag(_ code:String)->String {
        let scalars = code.uppercased().unicodeScalars
        guard scalars.count == 2,scalars.allSatisfy({(65...90).contains($0.value)}) else { return "🌐" }
        return String(String.UnicodeScalarView(scalars.compactMap { UnicodeScalar(127397+$0.value) }))
    }
}
