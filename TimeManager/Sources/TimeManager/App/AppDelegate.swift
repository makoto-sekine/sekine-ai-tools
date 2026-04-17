import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var store: SlotStore!
    private(set) var clock: CurrentTimeObserver!
    private var windowCoordinator: WindowCoordinator!
    private var menuBar: MenuBarController!
    private var notifications: NotificationScheduler!
    private var dayRolloverTimer: Timer?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        self.store = SlotStore()
        self.clock = CurrentTimeObserver()
        self.windowCoordinator = WindowCoordinator(store: store, clock: clock)
        self.menuBar = MenuBarController(store: store, windowCoordinator: windowCoordinator, appDelegate: self)
        self.notifications = NotificationScheduler(store: store, windowCoordinator: windowCoordinator)

        windowCoordinator.show()

        if !store.settings.onboardingCompleted {
            presentOnboarding()
        } else {
            notifications.rescheduleAll()
        }

        scheduleMidnightRollover()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowCoordinator.show()
        return true
    }

    // MARK: - Public helpers invoked by MenuBarController

    func copyCurrentDayMarkdown() {
        let text = MarkdownExporter.render(day: store.day, tags: store.tags)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func refreshNotifications() {
        notifications.rescheduleAll()
    }

    // MARK: - Onboarding

    private func presentOnboarding() {
        let root = OnboardingView(
            store: store,
            onRequestNotifications: { [weak self] completion in
                self?.notifications.requestAuthorization(completion: completion)
            },
            onRequestLoginItem: { enabled in
                LoginItemManager.setEnabled(enabled)
            },
            onClose: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                self?.notifications.rescheduleAll()
            }
        )
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.title = "TimeManager セットアップ"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.onboardingWindow = window
    }

    // MARK: - Day rollover

    private func scheduleMidnightRollover() {
        dayRolloverTimer?.invalidate()
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: Date()).addingTimeInterval(24 * 60 * 60 + 1)
        let interval = tomorrow.timeIntervalSinceNow
        let timer = Timer(timeInterval: max(interval, 60), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.store.currentDay == .today(calendar: calendar).adding(days: -1) {
                    self.store.goToToday()
                }
                self.notifications.resetUnansweredOnDayChange()
                self.notifications.rescheduleAll()
                self.scheduleMidnightRollover()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dayRolloverTimer = timer
    }
}
