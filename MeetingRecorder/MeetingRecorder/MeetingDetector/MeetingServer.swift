import Foundation
import Network

// =============================================================================
// MeetingServer - Chrome拡張機能からの通知を受け取るHTTPサーバー
// =============================================================================
// このクラスはローカルでHTTPサーバーを起動し、
// Chrome拡張機能からの会議開始/終了通知を受け取ります。
//
// ポート: 52828
// エンドポイント: POST /meeting-event
// =============================================================================

/// 会議イベントの種類
enum MeetingEvent: String, Codable {
    case meetingStart = "meeting_start"
    case meetingEnd = "meeting_end"
}

/// Chrome拡張機能から受け取るイベントデータ
struct MeetingEventData: Codable {
    let event: String
    let meetingCode: String?
    let meetingTitle: String?
    let timestamp: String?
}

/// サーバーのデリゲートプロトコル
protocol MeetingServerDelegate: AnyObject {
    func meetingDidStart(title: String, code: String?)
    func meetingDidEnd()
    func meetingTitleDidUpdate(title: String)
}

class MeetingServer {

    // -------------------------------------------------------------------------
    // プロパティ
    // -------------------------------------------------------------------------

    /// デリゲート
    weak var delegate: MeetingServerDelegate?

    /// サーバーのリスナー
    private var listener: NWListener?

    /// サーバーが起動中かどうか
    private(set) var isRunning: Bool = false

    /// サーバーのポート番号
    private let port: UInt16 = 52828

    /// 現在の会議状態
    private(set) var currentMeetingTitle: String?

    // -------------------------------------------------------------------------
    // サーバーの起動・停止
    // -------------------------------------------------------------------------

    /// サーバーを起動する
    func start() {
        guard !isRunning else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("MeetingServer started on port \(self?.port ?? 0)")
                    self?.isRunning = true
                case .failed(let error):
                    print("MeetingServer failed: \(error)")
                    self?.isRunning = false
                case .cancelled:
                    print("MeetingServer cancelled")
                    self?.isRunning = false
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: .main)

        } catch {
            print("Failed to start MeetingServer: \(error)")
        }
    }

    /// サーバーを停止する
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        print("MeetingServer stopped")
    }

    // -------------------------------------------------------------------------
    // 接続の処理
    // -------------------------------------------------------------------------

    /// 新しい接続を処理する
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)

        // データを受信
        receiveData(from: connection)
    }

    /// データを受信する
    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("Receive error: \(error)")
                connection.cancel()
                return
            }

            if let data = data, !data.isEmpty {
                self?.processHTTPRequest(data: data, connection: connection)
            }

            if isComplete {
                connection.cancel()
            }
        }
    }

    // -------------------------------------------------------------------------
    // HTTPリクエストの処理
    // -------------------------------------------------------------------------

    /// HTTPリクエストを処理する
    private func processHTTPRequest(data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }

        // HTTPリクエストをパース
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }

        let method = parts[0]
        let path = parts[1]

        // CORSプリフライトリクエストの処理
        if method == "OPTIONS" {
            sendCORSResponse(connection: connection)
            return
        }

        // POSTリクエストの処理
        if method == "POST" && path == "/meeting-event" {
            // ボディを抽出（空行以降）
            if let bodyStart = request.range(of: "\r\n\r\n") {
                let bodyString = String(request[bodyStart.upperBound...])
                handleMeetingEvent(body: bodyString, connection: connection)
            } else {
                sendResponse(connection: connection, statusCode: 400, body: "No body")
            }
            return
        }

        // GETリクエスト（ヘルスチェック用）
        if method == "GET" && path == "/health" {
            sendResponse(connection: connection, statusCode: 200, body: "{\"status\":\"ok\"}")
            return
        }

        sendResponse(connection: connection, statusCode: 404, body: "Not Found")
    }

    /// 会議イベントを処理する
    private func handleMeetingEvent(body: String, connection: NWConnection) {
        guard let data = body.data(using: .utf8) else {
            sendResponse(connection: connection, statusCode: 400, body: "Invalid body")
            return
        }

        do {
            let eventData = try JSONDecoder().decode(MeetingEventData.self, from: data)

            DispatchQueue.main.async { [weak self] in
                self?.processEvent(eventData)
            }

            sendResponse(connection: connection, statusCode: 200, body: "{\"status\":\"received\"}")

        } catch {
            print("JSON decode error: \(error)")
            sendResponse(connection: connection, statusCode: 400, body: "Invalid JSON")
        }
    }

    /// イベントを処理してデリゲートに通知
    private func processEvent(_ eventData: MeetingEventData) {
        let title = eventData.meetingTitle ?? "GoogleMeet"

        switch eventData.event {
        case "meeting_start":
            print("Meeting started: \(title)")
            currentMeetingTitle = title
            delegate?.meetingDidStart(title: title, code: eventData.meetingCode)

        case "meeting_end":
            print("Meeting ended: \(title)")
            currentMeetingTitle = nil
            delegate?.meetingDidEnd()

        case "meeting_title_updated":
            print("Meeting title updated: \(title)")
            currentMeetingTitle = title
            delegate?.meetingTitleDidUpdate(title: title)

        default:
            print("Unknown event: \(eventData.event)")
        }
    }

    // -------------------------------------------------------------------------
    // HTTPレスポンスの送信
    // -------------------------------------------------------------------------

    /// HTTPレスポンスを送信する
    private func sendResponse(connection: NWConnection, statusCode: Int, body: String) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Unknown"
        }

        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: POST, GET, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("Send error: \(error)")
                }
                connection.cancel()
            })
        }
    }

    /// CORSプリフライトレスポンスを送信する
    private func sendCORSResponse(connection: NWConnection) {
        let response = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: POST, GET, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Access-Control-Max-Age: 86400\r
        Connection: close\r
        \r

        """

        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
