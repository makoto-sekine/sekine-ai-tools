import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: SlotStore
    let onRequestNotifications: (@escaping (NotificationAuthorizationState) -> Void) -> Void
    let onRequestLoginItem: (Bool) -> Void
    let onClose: () -> Void

    @State private var step: Int = 0
    @State private var notificationState: NotificationAuthorizationState = .notDetermined
    @State private var autoLaunch: Bool = true
    @State private var startHour: Int = 10
    @State private var endHour: Int = 19

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 460)
    }

    private var header: some View {
        HStack {
            Text("TimeManager へようこそ")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Text("Step \(step + 1) / 4")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            welcomeStep
        case 1:
            notificationStep
        case 2:
            rangeStep
        default:
            finishStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("デスクトップ背面に常駐するタイムラインに、30分単位で作業記録を残せます。")
            Text("データは `~/TimeManager/` 配下の JSON ファイルに保存され、Finder から直接確認できます。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var notificationStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("30分ごとに macOS の通知で記入を促します。")
            Button("通知を許可する") {
                onRequestNotifications { state in
                    notificationState = state
                }
            }
            Text(statusLabel)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var statusLabel: String {
        switch notificationState {
        case .notDetermined: return "まだ許可ダイアログを出していません"
        case .authorized: return "通知の許可を取得しました"
        case .denied: return "拒否されました。通知なしでも利用可能です"
        }
    }

    private var rangeStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("既定の表示範囲を設定します（範囲外の記録で自動拡張されます）。")
            HStack {
                Stepper("開始: \(String(format: "%02d", startHour)):00", value: $startHour, in: 0...23)
                Stepper("終了: \(String(format: "%02d", endHour)):00", value: $endHour, in: 0...24)
            }
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最後に自動起動の設定です。")
            Toggle("ログイン時に自動起動する", isOn: $autoLaunch)
            Text("後からメニューバーの設定で変更できます。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("戻る") { step -= 1 }
            }
            Spacer()
            Button(step < 3 ? "次へ" : "はじめる") {
                if step < 3 { step += 1 } else { finish() }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func finish() {
        onRequestLoginItem(autoLaunch)
        store.updateSettings { settings in
            settings.defaultStartMinute = max(0, min(startHour, 23)) * 60
            settings.defaultEndMinute = max(startHour + 1, min(endHour, 24)) * 60
            settings.onboardingCompleted = true
        }
        onClose()
    }
}
