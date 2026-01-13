import AppKit
import SwiftUI
import UserNotifications

// =============================================================================
// AppDelegate - アプリケーションのメインクラス
// =============================================================================
// このクラスはアプリケーション全体のライフサイクルを管理します。
// macOSのメニューバーに常駐し、録音の開始・停止を制御します。
// =============================================================================

class AppDelegate: NSObject, NSApplicationDelegate {

    // -------------------------------------------------------------------------
    // プロパティ（クラスが保持するデータ）
    // -------------------------------------------------------------------------

    /// メニューバーに表示されるアイコン（ステータスアイテム）
    private var statusItem: NSStatusItem!

    /// 録音を管理するマネージャークラス
    private var recordingManager: RecordingManager!

    /// 現在録音中かどうかを示すフラグ
    private var isRecording = false

    /// 録音開始時刻（経過時間の計算に使用）
    private var recordingStartTime: Date?

    /// 録音時間を更新するためのタイマー
    private var timer: Timer?

    /// Google Meet自動検知クラス
    private var googleMeetDetector: GoogleMeetDetector!

    /// 自動検知が有効かどうか（UserDefaultsに保存）
    private var isAutoDetectionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "isAutoDetectionEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "isAutoDetectionEnabled")
            updateAutoDetection()
        }
    }

    /// 自動検知で録音が開始されたかどうか
    private var isAutoRecording: Bool = false

    /// 検知中の会議タイトル（通知から録音開始する際に使用）
    private var pendingMeetingTitle: String?

    /// 通知カテゴリID
    private let meetingDetectedCategoryId = "MEETING_DETECTED"
    private let startRecordingActionId = "START_RECORDING"

    // -------------------------------------------------------------------------
    // アプリケーション起動時の処理
    // -------------------------------------------------------------------------

    /// アプリケーションが起動した時に呼ばれるメソッド
    /// - Parameter notification: 起動通知オブジェクト
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dockにアイコンを表示しない（メニューバー常駐アプリにする）
        NSApp.setActivationPolicy(.accessory)

        // 録音マネージャーを初期化
        recordingManager = RecordingManager()

        // 通知の設定
        setupNotifications()

        // Google Meet検知を初期化
        googleMeetDetector = GoogleMeetDetector()
        googleMeetDetector.delegate = self

        // 前回の設定を復元（自動検知が有効だった場合は開始）
        if isAutoDetectionEnabled {
            googleMeetDetector.startDetection()
        }

        // メニューバーにアイコンを設置
        setupStatusItem()
    }

    // -------------------------------------------------------------------------
    // 通知のセットアップ
    // -------------------------------------------------------------------------

    /// 通知センターの設定を行う
    private func setupNotifications() {
        // バンドル識別子の確認（デバッグ用）
        if Bundle.main.bundleIdentifier == nil {
            print("Warning: Bundle identifier is nil. Notifications may not work properly.")
            print("Consider building with Xcode or creating a proper .app bundle.")
            return
        }

        // 少し遅延してから通知を設定（バンドルの初期化を待つ）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.configureNotificationCenter()
        }
    }

    /// 通知センターの実際の設定
    private func configureNotificationCenter() {
        let center = UNUserNotificationCenter.current()

        // デリゲートを設定
        center.delegate = self

        // 通知権限をリクエスト
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
            print("Notification authorization granted: \(granted)")
        }

        // 「録音開始」アクションを定義
        let startAction = UNNotificationAction(
            identifier: startRecordingActionId,
            title: "録音開始",
            options: [.foreground]
        )

        // カテゴリを定義（会議検知通知用）
        let meetingCategory = UNNotificationCategory(
            identifier: meetingDetectedCategoryId,
            actions: [startAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([meetingCategory])
    }

    // -------------------------------------------------------------------------
    // メニューバーのセットアップ
    // -------------------------------------------------------------------------

    /// メニューバーにステータスアイテム（アイコン）を設置する
    private func setupStatusItem() {
        // システムのメニューバーにアイテムを追加
        // variableLengthは内容に応じて幅が変わる設定
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // ボタン（アイコン部分）の設定
        if let button = statusItem.button {
            // SF Symbolsのマイクアイコンを使用
            button.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "Meeting Recorder")
        }

        // メニューの内容を設定
        updateMenu()
    }

    // -------------------------------------------------------------------------
    // メニュー内容の更新
    // -------------------------------------------------------------------------

    /// メニューの内容を現在の状態に合わせて更新する
    /// 録音中と待機中で表示内容が変わる
    private func updateMenu() {
        // 新しいメニューを作成
        let menu = NSMenu()

        if isRecording {
            // ----- 録音中の場合 -----

            // 録音中ステータスを赤文字で表示
            let statusItem = NSMenuItem(title: "● 録音中", action: nil, keyEquivalent: "")
            statusItem.attributedTitle = NSAttributedString(
                string: "● 録音中",
                attributes: [.foregroundColor: NSColor.systemRed]
            )
            menu.addItem(statusItem)

            // 経過時間を表示
            let durationItem = NSMenuItem(title: "  経過時間: \(formattedDuration())", action: nil, keyEquivalent: "")
            menu.addItem(durationItem)

            // セパレーター（区切り線）を追加
            menu.addItem(NSMenuItem.separator())

            // 録音停止ボタン（ショートカットキー: Cmd+R）
            let stopItem = NSMenuItem(title: "録音停止", action: #selector(toggleRecording), keyEquivalent: "r")
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            // ----- 待機中の場合 -----

            // 待機中ステータスを表示
            let statusItem = NSMenuItem(title: "○ 待機中", action: nil, keyEquivalent: "")
            menu.addItem(statusItem)

            // セパレーター（区切り線）を追加
            menu.addItem(NSMenuItem.separator())

            // 録音開始ボタン（ショートカットキー: Cmd+R）
            let startItem = NSMenuItem(title: "録音開始", action: #selector(toggleRecording), keyEquivalent: "r")
            startItem.target = self
            menu.addItem(startItem)
        }

        // セパレーター（区切り線）を追加
        menu.addItem(NSMenuItem.separator())

        // ----- 自動検知セクション -----

        // 自動検知のON/OFFトグル（ショートカットキー: Cmd+D）
        let autoDetectItem = NSMenuItem(
            title: isAutoDetectionEnabled ? "自動検知: ON" : "自動検知: OFF",
            action: #selector(toggleAutoDetection),
            keyEquivalent: "d"
        )
        autoDetectItem.target = self
        if isAutoDetectionEnabled {
            autoDetectItem.state = .on
        }
        menu.addItem(autoDetectItem)

        // 検知中の会議タイトルを表示（自動検知が有効で会議中の場合）
        if isAutoDetectionEnabled {
            if case .inMeeting(let title) = googleMeetDetector.currentState {
                let meetingStatusItem = NSMenuItem(
                    title: "  検知中: \(title)",
                    action: nil,
                    keyEquivalent: ""
                )
                meetingStatusItem.attributedTitle = NSAttributedString(
                    string: "  検知中: \(title)",
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                )
                menu.addItem(meetingStatusItem)
            }
        }

        // セパレーター（区切り線）を追加
        menu.addItem(NSMenuItem.separator())

        // 録音フォルダを開くボタン（ショートカットキー: Cmd+O）
        let openFolderItem = NSMenuItem(title: "録音フォルダを開く", action: #selector(openRecordingsFolder), keyEquivalent: "o")
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        // セパレーター（区切り線）を追加
        menu.addItem(NSMenuItem.separator())

        // 終了ボタン（ショートカットキー: Cmd+Q）
        let quitItem = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // 作成したメニューをステータスアイテムに設定
        statusItem.menu = menu
    }

    // -------------------------------------------------------------------------
    // 録音の開始・停止
    // -------------------------------------------------------------------------

    /// 録音の開始・停止を切り替える
    /// メニューから呼び出される（@objcはObjective-Cからも呼び出せるようにする指定）
    @objc private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// 録音を開始する
    private func startRecording() {
        // Task: 非同期処理を実行するためのブロック
        Task {
            do {
                // 録音マネージャーに録音開始を依頼
                // awaitは非同期処理の完了を待つ
                try await recordingManager.startRecording()

                // MainActor.run: UIの更新はメインスレッドで行う必要がある
                await MainActor.run {
                    self.isRecording = true
                    self.recordingStartTime = Date()  // 開始時刻を記録
                    self.updateStatusIcon(recording: true)  // アイコンを録音中に変更
                    self.startTimer()  // 経過時間更新用タイマーを開始
                    self.updateMenu()  // メニューを更新

                    // ユーザーに通知を表示
                    self.showNotification(
                        title: "録音開始",
                        body: "録音を開始しました"
                    )
                }
            } catch {
                // エラーが発生した場合
                await MainActor.run {
                    self.showAlert(title: "エラー", message: "録音を開始できませんでした: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 会議タイトル付きで録音を開始する（自動検知用）
    private func startRecordingWithMeetingTitle(_ title: String) {
        // 会議タイトルをRecordingManagerに設定
        recordingManager.currentMeetingTitle = title
        isAutoRecording = true
        startRecording()
    }

    /// 録音を停止する
    private func stopRecording() {
        // Task: 非同期処理を実行するためのブロック
        Task {
            // 録音マネージャーに録音停止を依頼し、保存されたファイルのURLを取得
            let savedURL = await recordingManager.stopRecording()

            // MainActor.run: UIの更新はメインスレッドで行う必要がある
            await MainActor.run {
                self.isRecording = false
                self.recordingStartTime = nil
                self.updateStatusIcon(recording: false)  // アイコンを待機中に変更
                self.stopTimer()  // タイマーを停止
                self.updateMenu()  // メニューを更新

                // 保存成功時に通知を表示
                if let url = savedURL {
                    self.showNotification(
                        title: "録音完了",
                        body: "保存先: \(url.lastPathComponent)"
                    )
                }

                // 自動録音の状態をリセット
                if self.isAutoRecording {
                    self.isAutoRecording = false
                    self.recordingManager.currentMeetingTitle = nil
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // アイコンの更新
    // -------------------------------------------------------------------------

    /// ステータスアイコンを録音状態に合わせて更新する
    /// - Parameter recording: 録音中かどうか
    private func updateStatusIcon(recording: Bool) {
        if let button = statusItem.button {
            // 録音中は塗りつぶしアイコン、待機中は輪郭だけのアイコン
            let symbolName = recording ? "mic.circle.fill" : "mic.circle"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Meeting Recorder")
            // 録音中は赤色にする
            button.contentTintColor = recording ? .systemRed : nil
        }
    }

    // -------------------------------------------------------------------------
    // タイマー管理（経過時間の表示用）
    // -------------------------------------------------------------------------

    /// 経過時間表示を更新するタイマーを開始する
    private func startTimer() {
        // 1秒ごとにメニューを更新（経過時間の表示を更新）
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // [weak self]: メモリリークを防ぐための弱参照
            self?.updateMenu()
        }
    }

    /// タイマーを停止する
    private func stopTimer() {
        timer?.invalidate()  // タイマーを無効化
        timer = nil
    }

    /// 経過時間を「時:分:秒」形式の文字列に変換する
    /// - Returns: "HH:MM:SS" 形式の文字列
    private func formattedDuration() -> String {
        // 開始時刻がなければデフォルト値を返す
        guard let startTime = recordingStartTime else { return "00:00:00" }

        // 現在時刻と開始時刻の差分（秒数）を計算
        let duration = Date().timeIntervalSince(startTime)

        // 時・分・秒に分解
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        // ゼロ埋めした文字列を返す
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    // -------------------------------------------------------------------------
    // その他のアクション
    // -------------------------------------------------------------------------

    /// 録音フォルダをFinderで開く
    @objc private func openRecordingsFolder() {
        let folderURL = recordingManager.recordingsFolder
        NSWorkspace.shared.open(folderURL)
    }

    /// アプリケーションを終了する
    @objc private func quit() {
        // 録音中の場合は先に停止する
        if isRecording {
            stopRecording()
        }
        NSApp.terminate(nil)
    }

    // -------------------------------------------------------------------------
    // 通知とアラート
    // -------------------------------------------------------------------------

    /// ユーザーに通知を表示する（シンプル通知）
    /// - Parameters:
    ///   - title: 通知のタイトル
    ///   - body: 通知の本文
    private func showNotification(title: String, body: String) {
        // バンドル識別子がない場合はログ出力のみ
        guard Bundle.main.bundleIdentifier != nil else {
            print("[\(title)] \(body)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // 即座に表示
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }

    /// 会議検知通知を表示する（アクション付き）
    /// - Parameter title: 検知された会議タイトル
    private func showMeetingDetectedNotification(title: String) {
        // バンドル識別子がない場合はアラートダイアログで代替
        guard Bundle.main.bundleIdentifier != nil else {
            DispatchQueue.main.async {
                self.showMeetingDetectedAlert(title: title)
            }
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Google Meet検知"
        content.body = "「\(title)」に参加中です。録音しますか？"
        content.sound = .default
        content.categoryIdentifier = meetingDetectedCategoryId

        // 会議タイトルを通知に保存
        content.userInfo = ["meetingTitle": title]

        let request = UNNotificationRequest(
            identifier: "meeting-detected-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Meeting notification error: \(error)")
                // 通知が失敗した場合はアラートで代替
                DispatchQueue.main.async {
                    self.showMeetingDetectedAlert(title: title)
                }
            }
        }
    }

    /// 会議検知時のアラートダイアログを表示する（通知のフォールバック）
    /// - Parameter title: 検知された会議タイトル
    private func showMeetingDetectedAlert(title: String) {
        let alert = NSAlert()
        alert.messageText = "Google Meet検知"
        alert.informativeText = "「\(title)」に参加中です。録音しますか？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "録音開始")
        alert.addButton(withTitle: "キャンセル")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            startRecordingWithMeetingTitle(title)
        }
    }

    /// エラーアラートを表示する
    /// - Parameters:
    ///   - title: アラートのタイトル
    ///   - message: アラートのメッセージ
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()  // モーダル表示（ユーザーが閉じるまで待機）
    }

    // -------------------------------------------------------------------------
    // 自動検知の管理
    // -------------------------------------------------------------------------

    /// 自動検知の状態を更新する
    private func updateAutoDetection() {
        if isAutoDetectionEnabled {
            googleMeetDetector.startDetection()
        } else {
            googleMeetDetector.stopDetection()
        }
        updateMenu()
    }

    /// 自動検知のON/OFFを切り替える
    @objc private func toggleAutoDetection() {
        isAutoDetectionEnabled.toggle()
    }
}

// =============================================================================
// UNUserNotificationCenterDelegate - 通知のデリゲート実装
// =============================================================================

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// 通知がフォアグラウンドで表示される時に呼ばれる
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // フォアグラウンドでも通知を表示
        completionHandler([.banner, .sound])
    }

    /// 通知のアクションが実行された時に呼ばれる
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionId = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo

        switch actionId {
        case startRecordingActionId:
            // 「録音開始」ボタンが押された
            if let meetingTitle = userInfo["meetingTitle"] as? String {
                DispatchQueue.main.async {
                    self.startRecordingWithMeetingTitle(meetingTitle)
                }
            }

        case UNNotificationDefaultActionIdentifier:
            // 通知自体がクリックされた（アクションボタン以外）
            if let meetingTitle = userInfo["meetingTitle"] as? String {
                DispatchQueue.main.async {
                    self.startRecordingWithMeetingTitle(meetingTitle)
                }
            }

        default:
            break
        }

        completionHandler()
    }
}

// =============================================================================
// GoogleMeetDetectorDelegate - 会議検知のデリゲート実装
// =============================================================================

extension AppDelegate: GoogleMeetDetectorDelegate {

    /// 会議が開始された時に呼ばれる
    /// - Parameter title: 検知された会議タイトル
    func meetingDidStart(title: String) {
        // 既に録音中の場合は何もしない
        guard !isRecording else { return }

        // 検知中の会議タイトルを保存
        pendingMeetingTitle = title

        // 通知を表示（ユーザーに録音開始を促す）
        showMeetingDetectedNotification(title: title)

        // メニューを更新（検知中の表示）
        DispatchQueue.main.async {
            self.updateMenu()
        }
    }

    /// 会議が終了した時に呼ばれる
    func meetingDidEnd() {
        // 検知中の会議タイトルをクリア
        pendingMeetingTitle = nil

        // 自動録音中の場合のみ停止
        if isAutoRecording {
            stopRecording()
        }

        // メニューを更新
        DispatchQueue.main.async {
            self.updateMenu()
        }
    }

    /// 会議タイトルが更新された時に呼ばれる
    func meetingTitleDidUpdate(title: String) {
        // 録音中の場合はタイトルを更新
        if isAutoRecording {
            recordingManager.currentMeetingTitle = title
            print("Recording title updated: \(title)")
        }

        // 検知中のタイトルも更新
        pendingMeetingTitle = title

        // メニューを更新
        DispatchQueue.main.async {
            self.updateMenu()
        }
    }
}
