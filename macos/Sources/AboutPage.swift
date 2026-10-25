import SwiftUI

struct AboutPage: View {
    @ObservedObject private var interface = InterfacePreferences.shared
    @Environment(\.veil) private var palette
    let version: String

    var body: some View {
        VStack(alignment:.leading,spacing:V(20)) {
            HStack(spacing:V(16)) {
                Image(systemName:"play.rectangle.on.rectangle")
                    .font(.veil(size:30,weight:.light)).foregroundStyle(palette.accent)
                    .frame(width:V(62),height:V(62))
                    .background(palette.accent.opacity(0.12),in:RoundedRectangle(cornerRadius:V(18)))
                VStack(alignment:.leading,spacing:V(6)) {
                    Text("CapCut Launcher").font(.veil(size:22,weight:.semibold))
                    Text(L("Версия \(version)")).font(.veil(size:12)).foregroundStyle(.secondary)
                    Text(L("Независимый лаунчер для CapCut."))
                        .font(.veil(size:12)).foregroundStyle(.secondary)
                }
            }.padding(.vertical,V(8))

            VStack(alignment:.leading,spacing:V(22)) {
                feature("sparkles",title:"Pro-интерфейс и регионы",
                    detail:"Включает корректное отображение Pro-интерфейса и позволяет выбрать регион ресурсов CapCut.")
                feature("person.crop.circle.badge.checkmark",title:"Вход по почте и паролю",
                    detail:"Добавляет прямой вход в аккаунт CapCut из профиля лаунчера и сохраняет отдельные браузерные сеансы.")
                feature("folder",title:"Удобное управление проектами",
                    detail:"Показывает проекты с обложками. Позволяет импортировать, экспортировать, переносить и восстанавливать их из корзины лаунчера.")
                feature("magnifyingglass",title:"Поиск на русском языке",
                    detail:"Исправляет кодировку русских поисковых запросов. Эффекты, переходы, стикеры, шаблоны и анимации текста можно искать на русском языке.")
            }.surface()

            VStack(alignment:.leading,spacing:V(10)) {
                Label(L("Ваши данные"),systemImage:"lock.shield")
                    .font(.veil(size:14,weight:.semibold)).foregroundStyle(palette.accent)
                paragraph("Профили, браузерные сеансы и проекты хранятся локально на вашем Mac. Пароли сохраняются в Связке ключей macOS.")
                paragraph("Для входа и работы CapCut данные передаются официальным сервисам CapCut. При выбранном входе через Google или Apple участвует соответствующий сервис авторизации. Проверка и загрузка обновлений выполняются через GitHub.")
            }.surface()

            VStack(alignment:.leading,spacing:V(10)) {
                Label(L("Перед использованием"),systemImage:"exclamationmark.shield")
                    .font(.veil(size:14,weight:.semibold))
                paragraph("Возможны ошибки, зависания и вылеты. Используйте лаунчер на свой риск: ответственность за аккаунт, сохранность проектов и последствия использования остаётся за вами. Делайте резервные копии важных проектов.")
                paragraph("Лаунчер не связан с ByteDance и не гарантирует отсутствие ограничений аккаунта. Отображение Pro-интерфейса не заменяет подписку: доступ к платным функциям и экспорту определяет CapCut.")
            }.surface()
        }.frame(maxWidth:.infinity,alignment:.leading)
    }

    private func feature(_ icon:String,title:String,detail:String) -> some View {
        HStack(alignment:.top,spacing:V(14)) {
            Image(systemName:icon).font(.veil(size:18)).foregroundStyle(palette.accent)
                .frame(width:V(34),height:V(34))
                .background(palette.accent.opacity(0.08),in:RoundedRectangle(cornerRadius:V(10)))
            VStack(alignment:.leading,spacing:V(6)) {
                Text(L(title)).font(.veil(size:14,weight:.semibold))
                paragraph(detail)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }

    private func paragraph(_ text:String) -> some View {
        Text(L(text)).font(.veil(size:12)).foregroundStyle(.secondary)
            .fixedSize(horizontal:false,vertical:true)
    }
}
