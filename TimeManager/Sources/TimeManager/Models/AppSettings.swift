import Foundation

struct AppSettings: Codable {
    var defaultStartMinute: Int
    var defaultEndMinute: Int
    var notificationEnabled: Bool
    var notificationIntervalMinutes: Int
    var autoMergeSameTag: Bool
    var onboardingCompleted: Bool
    var schemaVersion: Int

    static let current = AppSettings(
        defaultStartMinute: MinuteOfDay.defaultStart.value,
        defaultEndMinute: MinuteOfDay.defaultEnd.value,
        notificationEnabled: true,
        notificationIntervalMinutes: 30,
        autoMergeSameTag: false,
        onboardingCompleted: false,
        schemaVersion: 1
    )
}
