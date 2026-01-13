import Foundation

// =============================================================================
// GoogleMeetDetector - Chrome拡張機能経由でGoogle Meet会議を検知するクラス
// =============================================================================
// このクラスはMeetingServer（HTTPサーバー）を使用して、
// Chrome拡張機能からの会議開始・終了通知を受け取ります。
//
// 【仕組み】
// 1. アプリがローカルHTTPサーバー（ポート52828）を起動
// 2. Chrome拡張機能がGoogle Meetの参加・退出を検知
// 3. 拡張機能がHTTP POSTでアプリに通知
// 4. アプリがデリゲートを通じて録音を制御
// =============================================================================

/// 会議の状態を表す列挙型
enum MeetingState: Equatable {
    /// 会議に参加していない
    case notInMeeting
    /// 会議に参加中（会議タイトルを保持）
    case inMeeting(title: String)
}

/// 会議検知のデリゲートプロトコル
protocol GoogleMeetDetectorDelegate: AnyObject {
    /// 会議が開始された時に呼ばれる
    func meetingDidStart(title: String)
    /// 会議が終了した時に呼ばれる
    func meetingDidEnd()
    /// 会議タイトルが更新された時に呼ばれる（オプション）
    func meetingTitleDidUpdate(title: String)
}

// デフォルト実装（オプショナルにするため）
extension GoogleMeetDetectorDelegate {
    func meetingTitleDidUpdate(title: String) {}
}

class GoogleMeetDetector {

    // -------------------------------------------------------------------------
    // プロパティ
    // -------------------------------------------------------------------------

    /// デリゲート（状態変化を通知する先）
    weak var delegate: GoogleMeetDetectorDelegate?

    /// 自動検知が有効かどうか
    private(set) var isEnabled: Bool = false

    /// 現在の会議状態
    private(set) var currentState: MeetingState = .notInMeeting

    /// HTTPサーバー
    private var server: MeetingServer?

    // -------------------------------------------------------------------------
    // 自動検知の開始・停止
    // -------------------------------------------------------------------------

    /// 自動検知を開始する（HTTPサーバーを起動）
    func startDetection() {
        guard !isEnabled else { return }

        isEnabled = true
        currentState = .notInMeeting

        // サーバーを起動
        server = MeetingServer()
        server?.delegate = self
        server?.start()

        print("Google Meet detection started (HTTP server mode)")
    }

    /// 自動検知を停止する（HTTPサーバーを停止）
    func stopDetection() {
        guard isEnabled else { return }

        isEnabled = false
        currentState = .notInMeeting

        // サーバーを停止
        server?.stop()
        server = nil

        print("Google Meet detection stopped")
    }
}

// =============================================================================
// MeetingServerDelegate - サーバーからのイベントを処理
// =============================================================================

extension GoogleMeetDetector: MeetingServerDelegate {

    func meetingDidStart(title: String, code: String?) {
        guard isEnabled else { return }

        // 既に会議中の場合は無視
        if case .inMeeting = currentState {
            return
        }

        currentState = .inMeeting(title: title)

        // デリゲートに通知
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.meetingDidStart(title: title)
        }
    }

    func meetingDidEnd() {
        guard isEnabled else { return }

        // 会議中でない場合は無視
        guard case .inMeeting = currentState else {
            return
        }

        currentState = .notInMeeting

        // デリゲートに通知
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.meetingDidEnd()
        }
    }

    func meetingTitleDidUpdate(title: String) {
        guard isEnabled else { return }

        // 会議中の場合のみ更新
        if case .inMeeting = currentState {
            currentState = .inMeeting(title: title)

            // デリゲートに通知
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.meetingTitleDidUpdate(title: title)
            }
        }
    }
}
