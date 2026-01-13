import AppKit
import SwiftUI

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

        // メニューバーにアイコンを設置
        setupStatusItem()
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

    /// ユーザーに通知を表示する
    /// - Parameters:
    ///   - title: 通知のタイトル
    ///   - body: 通知の本文
    private func showNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName  // 通知音を鳴らす
        NSUserNotificationCenter.default.deliver(notification)
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
}
