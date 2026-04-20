import Foundation
import AVFoundation

// =============================================================================
// MicrophoneCapture - マイク音声をキャプチャするクラス
// =============================================================================
// このクラスはAVAudioEngine（Appleの音声処理フレームワーク）を使用して、
// マイクからの音声入力をリアルタイムでキャプチャします。
//
// 【重要】このクラスを使用するには「マイク」の権限が必要です。
// システム設定 > プライバシーとセキュリティ > マイク で許可してください。
// =============================================================================

class MicrophoneCapture {

    // -------------------------------------------------------------------------
    // プロパティ
    // -------------------------------------------------------------------------

    /// 音声処理エンジン
    /// AVAudioEngineは音声の入力、処理、出力を管理するクラス
    private var audioEngine: AVAudioEngine?

    /// 音声入力ノード（マイクからの入力を表す）
    /// ノード = 音声処理の1つの段階を表すオブジェクト
    private var inputNode: AVAudioInputNode?

    /// キャプチャした音声データを外部に渡すためのコールバック
    var audioDataHandler: ((AVAudioPCMBuffer) -> Void)?

    /// ノイズキャンセリングの有効/無効
    var isNoiseCancellationEnabled: Bool = false

    /// ノイズゲートのしきい値（-60dB = 0.001, 値より小さい音は無視）
    private let noiseGateThreshold: Float = 0.005

    // -------------------------------------------------------------------------
    // キャプチャの開始
    // -------------------------------------------------------------------------

    /// マイク音声のキャプチャを開始する
    /// - Throws: 権限がない場合やマイクが見つからない場合にエラーをスロー
    func start() throws {
        // マイクへのアクセス権限を確認
        // AVCaptureDevice: カメラやマイクなどのキャプチャデバイスを管理するクラス
        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        switch permissionStatus {
        case .notDetermined:
            // まだ権限を求めていない場合、ダイアログを表示して許可を求める
            // DispatchSemaphore: 非同期処理を同期的に待つための仕組み
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false

            // 権限リクエストダイアログを表示
            AVCaptureDevice.requestAccess(for: .audio) { result in
                granted = result
                semaphore.signal()  // 待機を解除
            }

            semaphore.wait()  // 結果が返ってくるまで待機

            guard granted else {
                throw MicrophoneError.permissionDenied
            }

        case .denied, .restricted:
            // 権限が拒否されている、または制限されている
            throw MicrophoneError.permissionDenied

        case .authorized:
            // 権限あり、そのまま続行
            break

        @unknown default:
            // 将来追加される可能性のある状態に対応
            break
        }

        // オーディオエンジンを作成
        audioEngine = AVAudioEngine()

        guard let audioEngine = audioEngine else {
            throw MicrophoneError.engineCreationFailed
        }

        // 入力ノード（マイク）を取得
        // inputNodeはAVAudioEngineが自動的に提供するマイク入力
        inputNode = audioEngine.inputNode

        guard let inputNode = inputNode else {
            throw MicrophoneError.noInputDevice
        }

        // 入力のフォーマット（サンプルレート、チャンネル数など）を取得
        // forBus: 0 = メインバス（通常の入出力で使用）
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // フォーマットが有効かチェック
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            throw MicrophoneError.invalidFormat
        }

        // ノイズキャンセリング機能を有効化
        // macOS 11.0以降で利用可能なVoice Processing機能を使用
        if #available(macOS 11.0, *), isNoiseCancellationEnabled {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                print("Voice processing (noise cancellation) enabled")
            } catch {
                print("Warning: Failed to enable voice processing: \(error)")
            }
        }

        // 入力ノードにタップ（データ取得ポイント）を設置
        // bufferSize: 一度に取得するサンプル数（4096 = 約85ms分@48kHz）
        // format: 取得するデータのフォーマット
        // クロージャ: データが利用可能になるたびに呼ばれる
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // ノイズゲート処理（小さすぎる音をカット）
            if self.isNoiseCancellationEnabled {
                self.applyNoiseGate(to: buffer)
            }

            // キャプチャしたデータをコールバックで外部に渡す
            self.audioDataHandler?(buffer)
        }

        // オーディオエンジンを開始
        try audioEngine.start()
        print("Microphone capture started")
    }

    // -------------------------------------------------------------------------
    // キャプチャの停止
    // -------------------------------------------------------------------------

    /// マイク音声のキャプチャを停止する
    func stop() {
        // タップを削除（データ取得を停止）
        inputNode?.removeTap(onBus: 0)

        // エンジンを停止
        audioEngine?.stop()

        // オブジェクトを解放
        audioEngine = nil
        inputNode = nil

        print("Microphone capture stopped")
    }

    // -------------------------------------------------------------------------
    // ノイズゲート処理
    // -------------------------------------------------------------------------

    /// ノイズゲート処理を適用（しきい値以下の音を0にする）
    /// - Parameter buffer: 処理対象の音声バッファ
    private func applyNoiseGate(to buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        // 各チャンネルに対して処理
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                let sample = floatData[channel][frame]
                let absoluteValue = abs(sample)

                // しきい値以下の音は0にする（ノイズとみなす）
                if absoluteValue < noiseGateThreshold {
                    floatData[channel][frame] = 0
                }
            }
        }
    }
}

// =============================================================================
// MicrophoneError - マイク関連のエラー定義
// =============================================================================
// LocalizedError: ユーザーに表示するエラーメッセージを提供するプロトコル
// =============================================================================

enum MicrophoneError: LocalizedError {
    /// マイクへのアクセス権限がない
    case permissionDenied
    /// オーディオエンジンの作成に失敗
    case engineCreationFailed
    /// マイク（入力デバイス）が見つからない
    case noInputDevice
    /// 音声フォーマットが無効
    case invalidFormat

    /// エラーメッセージを返す（ユーザーに表示される）
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "マイクへのアクセス権限が必要です。システム設定 > プライバシーとセキュリティ > マイク で許可してください。"
        case .engineCreationFailed:
            return "オーディオエンジンの作成に失敗しました。"
        case .noInputDevice:
            return "マイクが見つかりませんでした。"
        case .invalidFormat:
            return "オーディオフォーマットが無効です。"
        }
    }
}
