import Foundation
@preconcurrency import UserNotifications
import AppKit

enum NotificationAuthorizationState {
    case notDetermined
    case authorized
    case denied
}

@MainActor
final class NotificationScheduler: NSObject {
    static let categoryId = "co.brewus.timemanager.halfhour"
    static let actionOpen = "OPEN_SLOT"
    private let center = UNUserNotificationCenter.current()
    private let store: SlotStore
    private weak var windowCoordinator: WindowCoordinator?
    private let unanswerDefaultsKey = "TimeManager.unansweredCount"
    private let suppressDayDefaultsKey = "TimeManager.suppressedForDay"

    init(store: SlotStore, windowCoordinator: WindowCoordinator) {
        self.store = store
        self.windowCoordinator = windowCoordinator
        super.init()
        center.delegate = self
        registerCategories()
    }

    // MARK: - Permission

    func requestAuthorization(completion: @escaping (NotificationAuthorizationState) -> Void) {
        let center = self.center
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        completion(granted ? .authorized : .denied)
                    }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { completion(.authorized) }
            case .denied:
                DispatchQueue.main.async { completion(.denied) }
            @unknown default:
                DispatchQueue.main.async { completion(.denied) }
            }
        }
    }

    // MARK: - Scheduling

    func rescheduleAll() {
        center.removeAllPendingNotificationRequests()
        guard store.settings.notificationEnabled else { return }
        if isSuppressedForToday() { return }

        for hour in 0..<24 {
            for minute in stride(from: 0, through: 30, by: 30) {
                var components = DateComponents()
                components.hour = hour
                components.minute = minute

                let content = UNMutableNotificationContent()
                content.title = "TimeManager"
                content.body = "直前の30分、何をしていましたか？"
                content.sound = .default
                content.categoryIdentifier = Self.categoryId
                content.userInfo = ["slotMinute": hour * 60 + minute]

                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let id = "timemanager.\(String(format: "%02d%02d", hour, minute))"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                center.add(request, withCompletionHandler: nil)
            }
        }
    }

    private func registerCategories() {
        let openAction = UNNotificationAction(identifier: Self.actionOpen, title: "記入する", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    // MARK: - Unanswered tracking

    private func isSuppressedForToday() -> Bool {
        let stored = UserDefaults.standard.string(forKey: suppressDayDefaultsKey) ?? ""
        return stored == DayDate.today().key
    }

    func resetUnansweredOnDayChange() {
        UserDefaults.standard.set(0, forKey: unanswerDefaultsKey)
        UserDefaults.standard.removeObject(forKey: suppressDayDefaultsKey)
    }

    func recordUnanswered() {
        var count = UserDefaults.standard.integer(forKey: unanswerDefaultsKey)
        count += 1
        UserDefaults.standard.set(count, forKey: unanswerDefaultsKey)
        if count >= 3 {
            UserDefaults.standard.set(DayDate.today().key, forKey: suppressDayDefaultsKey)
            rescheduleAll()
        }
    }

    func recordAnswered() {
        UserDefaults.standard.set(0, forKey: unanswerDefaultsKey)
    }
}

extension NotificationScheduler: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let slotMinute = (response.notification.request.content.userInfo["slotMinute"] as? Int) ?? 0
        Task { @MainActor in
            self.recordAnswered()
            self.windowCoordinator?.bringToFrontTemporarily()
            let minute = MinuteOfDay(slotMinute)
            _ = self.store.ensureSlot(startingAt: minute)
            completionHandler()
        }
    }
}
