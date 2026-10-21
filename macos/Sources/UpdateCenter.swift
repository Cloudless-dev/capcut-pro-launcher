import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateCenter: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published var checking = false
    @Published var availableVersion: String?
    @Published var message = "Для этой сборки обновления пока не опубликованы."
    var controller: SPUStandardUpdaterController?
    var isCapCutRunning: (() -> Bool)?
    var configured: Bool { controller != nil }
    func configure(automatic: Bool) {
        guard let feed = Bundle.main.object(forInfoDictionaryKey:"SUFeedURL") as? String,
            feed.hasPrefix("https://"), Bundle.main.object(forInfoDictionaryKey:"SUPublicEDKey") != nil else { return }
        if controller == nil {
            controller = SPUStandardUpdaterController(startingUpdater:true,updaterDelegate:self,userDriverDelegate:nil)
            message = "Проверяйте новые версии или включите автообновления."
        }
        controller?.updater.automaticallyChecksForUpdates = automatic
        controller?.updater.automaticallyDownloadsUpdates = automatic
    }
    func check() {
        guard let controller, !checking else { return }
        checking = true; message = "Проверяю новые версии…"
        controller.updater.checkForUpdateInformation()
    }
    func install() {
        guard isCapCutRunning?() != true else {
            let alert = NSAlert(); alert.messageText = L("Сначала закройте CapCut")
            alert.informativeText = L("После закрытия можно установить новую версию лаунчера."); alert.runModal(); return
        }
        controller?.checkForUpdates(nil)
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        checking = false; availableVersion = item.displayVersionString; message = "Доступна версия \(item.displayVersionString)."
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        checking = false; availableVersion = nil; message = "Установлена последняя доступная версия."
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        checking = false
        if (error as NSError).code != Int(SUError.noUpdateError.rawValue) { message = "Не удалось проверить обновления. Повторите позже." }
    }
}
