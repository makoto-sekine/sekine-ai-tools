import Foundation
import AVFoundation

// =============================================================================
// RecordingManager - 録音全体を管理するクラス
// =============================================================================
// このクラスは録音処理の中心となるマネージャーです。
// システム音声とマイク音声のキャプチャを統括し、
// ミキシングして1つのファイルとして保存します。
// =============================================================================

class RecordingManager {

    // -------------------------------------------------------------------------
    // プロパティ（クラスが保持するデータ）
    // -------------------------------------------------------------------------

    /// システム音声（PCから出る音）をキャプチャするクラス
    private var systemAudioCapture: SystemAudioCapture?

    /// マイク音声をキャプチャするクラス
    private var microphoneCapture: MicrophoneCapture?

    /// システム音声とマイク音声をミックスするクラス
    private var audioMixer: AudioMixer?

    /// ミックスした音声をファイルに書き出すクラス
    private var audioExporter: AudioExporter?

    /// 現在録音中かどうかを示すフラグ
    private var isRecording = false

    /// 録音開始時刻（ファイル名の生成に使用）
    private var recordingStartTime: Date?

    /// 現在の会議タイトル（自動検知で設定）
    /// この値が設定されている場合、ファイル名に使用される
    var currentMeetingTitle: String?

    /// 録音ファイルを保存するフォルダのURL
    /// 外部からアクセス可能（録音フォルダを開く機能で使用）
    let recordingsFolder: URL

    // -------------------------------------------------------------------------
    // 初期化
    // -------------------------------------------------------------------------

    /// 初期化処理
    /// 録音ファイルを保存するフォルダを作成する
    init() {
        // ドキュメントフォルダのパスを取得
        // FileManager.defaultはファイル操作を行うシングルトンオブジェクト
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // 「MeetingRecordings」というサブフォルダを作成
        recordingsFolder = documentsPath.appendingPathComponent("MeetingRecordings")

        // フォルダが存在しない場合は作成
        // try? はエラーを無視する（フォルダが既に存在する場合など）
        try? FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)
    }

    // -------------------------------------------------------------------------
    // 録音の開始
    // -------------------------------------------------------------------------

    /// 録音を開始する
    /// - Throws: 録音開始に失敗した場合にエラーをスロー
    /// - Note: asyncは非同期関数であることを示す
    func startRecording() async throws {
        // 既に録音中の場合は何もしない
        guard !isRecording else { return }

        // 録音開始時刻を記録
        recordingStartTime = Date()

        // 各コンポーネントを初期化
        systemAudioCapture = SystemAudioCapture()
        microphoneCapture = MicrophoneCapture()
        audioMixer = AudioMixer()
        audioExporter = AudioExporter(outputFolder: recordingsFolder)

        // システム音声がキャプチャされた時のコールバックを設定
        // クロージャ内で self を使う場合は [weak self] でメモリリークを防ぐ
        systemAudioCapture?.audioDataHandler = { [weak self] buffer in
            // キャプチャしたシステム音声をミキサーに渡す
            self?.audioMixer?.addSystemAudio(buffer)
        }

        // マイク音声がキャプチャされた時のコールバックを設定
        microphoneCapture?.audioDataHandler = { [weak self] buffer in
            // キャプチャしたマイク音声をミキサーに渡す
            self?.audioMixer?.addMicrophoneAudio(buffer)
        }

        // キャプチャを開始
        // awaitで非同期処理の完了を待つ
        try await systemAudioCapture?.start()
        try microphoneCapture?.start()

        // 音声ファイルへの書き出しを開始
        try audioExporter?.startRecording()

        // ミキサーの出力をエクスポーターに渡すコールバックを設定
        audioMixer?.outputHandler = { [weak self] buffer in
            // ミックスされた音声をファイルに書き込む
            self?.audioExporter?.appendAudio(buffer)
        }

        isRecording = true
        print("Recording started")
    }

    // -------------------------------------------------------------------------
    // 録音の停止
    // -------------------------------------------------------------------------

    /// 録音を停止し、ファイルを保存する
    /// - Returns: 保存されたファイルのURL（失敗した場合はnil）
    func stopRecording() async -> URL? {
        // 録音中でない場合は何もしない
        guard isRecording else { return nil }

        isRecording = false

        // キャプチャを停止
        systemAudioCapture?.stop()
        microphoneCapture?.stop()

        // ファイル名を生成
        let filename = generateFilename()

        // エクスポーターに録音停止を通知し、ファイルを保存
        let outputURL = await audioExporter?.stopRecording(filename: filename)

        // 使用したオブジェクトを解放
        // nilを代入することでメモリを解放
        systemAudioCapture = nil
        microphoneCapture = nil
        audioMixer = nil
        audioExporter = nil
        recordingStartTime = nil

        print("Recording stopped: \(outputURL?.path ?? "no file")")
        return outputURL
    }

    // -------------------------------------------------------------------------
    // ファイル名の生成
    // -------------------------------------------------------------------------

    /// 録音ファイルのファイル名を生成する
    /// - Returns: 会議タイトルがあれば "タイトル_YYYY-MM-DD_HHMMSS" 形式、
    ///           なければ "recording_YYYY-MM-DD_HHMMSS" 形式のファイル名
    private func generateFilename() -> String {
        // 日付をフォーマットするためのフォーマッター
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"

        // 録音開始時刻を文字列に変換（開始時刻がない場合は現在時刻を使用）
        let dateString = formatter.string(from: recordingStartTime ?? Date())

        // 会議タイトルがあればそれを使用
        if let meetingTitle = currentMeetingTitle, !meetingTitle.isEmpty {
            return "\(meetingTitle)_\(dateString)"
        }

        return "recording_\(dateString)"
    }
}
