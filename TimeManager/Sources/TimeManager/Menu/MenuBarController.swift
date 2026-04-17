import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: SlotStore
    private weak var windowCoordinator: WindowCoordinator?
    private weak var appDelegate: AppDelegate?

    init(store: SlotStore, windowCoordinator: WindowCoordinator, appDelegate: AppDelegate) {
        self.store = store
        self.windowCoordinator = windowCoordinator
        self.appDelegate = appDelegate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        rebuildMenu()
    }

    private func configureButton() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "TimeManager")
            button.imagePosition = .imageOnly
            button.toolTip = "TimeManager"
        }
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: windowCoordinator?.isVisible() == true ? "タイムラインを隠す" : "タイムラインを表示",
            action: #selector(toggleWindow),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let pin = NSMenuItem(
            title: "最前面に切替 (Pin)",
            action: #selector(pinToggle),
            keyEquivalent: "p"
        )
        pin.target = self
        pin.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(pin)

        menu.addItem(.separator())

        let copyMd = NSMenuItem(
            title: "今日を Markdown でコピー",
            action: #selector(copyMarkdown),
            keyEquivalent: "c"
        )
        copyMd.target = self
        copyMd.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(copyMd)

        let openFolder = NSMenuItem(
            title: "データフォルダを Finder で開く",
            action: #selector(openDataFolder),
            keyEquivalent: ""
        )
        openFolder.target = self
        menu.addItem(openFolder)

        menu.addItem(.separator())

        let notifToggle = NSMenuItem(
            title: store.settings.notificationEnabled ? "30分通知: ON" : "30分通知: OFF",
            action: #selector(toggleNotifications),
            keyEquivalent: ""
        )
        notifToggle.target = self
        notifToggle.state = store.settings.notificationEnabled ? .on : .off
        menu.addItem(notifToggle)

        let autoMerge = NSMenuItem(
            title: store.settings.autoMergeSameTag ? "同タグ自動マージ: ON" : "同タグ自動マージ: OFF",
            action: #selector(toggleAutoMerge),
            keyEquivalent: ""
        )
        autoMerge.target = self
        autoMerge.state = store.settings.autoMergeSameTag ? .on : .off
        menu.addItem(autoMerge)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "TimeManager を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func toggleWindow() {
        guard let coordinator = windowCoordinator else { return }
        if coordinator.isVisible() { coordinator.hide() } else { coordinator.show() }
        rebuildMenu()
    }

    @objc private func pinToggle() {
        windowCoordinator?.pinToFrontToggle()
    }

    @objc private func copyMarkdown() {
        appDelegate?.copyCurrentDayMarkdown()
    }

    @objc private func openDataFolder() {
        let url = FileStoreLocation.root
        try? FileStoreLocation.ensureDirectoryStructure()
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleNotifications() {
        store.updateSettings { settings in
            settings.notificationEnabled.toggle()
        }
        appDelegate?.refreshNotifications()
        rebuildMenu()
    }

    @objc private func toggleAutoMerge() {
        store.updateSettings { settings in
            settings.autoMergeSameTag.toggle()
        }
        rebuildMenu()
    }
}
