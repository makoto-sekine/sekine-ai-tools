import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

// =============================================================================
// SystemAudioCapture - システム音声をキャプチャするクラス
// =============================================================================
// このクラスはmacOSのScreenCaptureKit（画面収録フレームワーク）を使用して、
// システムから出力される音声（他のアプリの音声など）をキャプチャします。
//
// 【重要】このクラスを使用するには「画面収録」の権限が必要です。
// システム設定 > プライバシーとセキュリティ > 画面収録 で許可してください。
// =============================================================================

class SystemAudioCapture: NSObject {

    // -------------------------------------------------------------------------
    // プロパティ
    // -------------------------------------------------------------------------

    /// ScreenCaptureKitのストリームオブジェクト
    /// 画面と音声をキャプチャするために使用
    private var stream: SCStream?

    /// ストリームからのデータを受け取るハンドラークラス
    private var streamOutput: StreamOutput?

    /// キャプチャした音声データを外部に渡すためのコールバック
    /// AVAudioPCMBuffer: PCM（非圧縮）形式の音声データを格納するバッファ
    var audioDataHandler: ((AVAudioPCMBuffer) -> Void)?

    // -------------------------------------------------------------------------
    // キャプチャの開始
    // -------------------------------------------------------------------------

    /// システム音声のキャプチャを開始する
    /// - Throws: 権限がない場合やディスプレイが見つからない場合にエラーをスロー
    func start() async throws {
        // 画面収録の権限をチェック
        // CGPreflightScreenCaptureAccess: 権限があるかどうかを事前確認
        guard CGPreflightScreenCaptureAccess() else {
            // 権限がない場合は権限リクエストダイアログを表示
            CGRequestScreenCaptureAccess()
            throw CaptureError.permissionDenied
        }

        // キャプチャ可能なコンテンツ（ディスプレイ、ウィンドウなど）を取得
        // excludingDesktopWindows: デスクトップウィンドウを除外するか
        // onScreenWindowsOnly: 画面上に表示されているウィンドウのみ取得するか
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        // メインディスプレイを取得
        guard let display = availableContent.displays.first else {
            throw CaptureError.noDisplayFound
        }

        // キャプチャ対象のフィルターを作成
        // 全画面をキャプチャ対象にする（音声だけが必要だが、画面指定が必須）
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // ストリームの設定を作成
        let configuration = SCStreamConfiguration()

        // 音声キャプチャを有効化
        configuration.capturesAudio = true

        // 自分自身（このアプリ）の音声は除外
        configuration.excludesCurrentProcessAudio = true

        // 音声のサンプリングレート（48kHz = 高品質）
        configuration.sampleRate = 48000

        // チャンネル数（2 = ステレオ）
        configuration.channelCount = 2

        // 映像キャプチャは最小限に（音声だけが必要なので）
        configuration.width = 2
        configuration.height = 2
        // フレームレートを最小に（1fps）
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        // カーソルを表示しない
        configuration.showsCursor = false

        // ストリーム出力ハンドラーを作成
        streamOutput = StreamOutput()

        // 音声データを受け取った時のコールバックを設定
        streamOutput?.audioHandler = { [weak self] sampleBuffer in
            self?.processSampleBuffer(sampleBuffer)
        }

        // ストリームを作成
        // delegate: ストリームのイベント（エラーなど）を受け取るオブジェクト
        stream = SCStream(filter: filter, configuration: configuration, delegate: streamOutput)

        // ストリーム出力を追加
        // type: .audio = 音声データを受け取る
        // sampleHandlerQueue: データを処理するスレッド（優先度高）
        try stream?.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        // 映像出力も追加（必須だが、データは無視する）
        try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: .global(qos: .background))

        // キャプチャを開始
        try await stream?.startCapture()
        print("System audio capture started")
    }

    // -------------------------------------------------------------------------
    // キャプチャの停止
    // -------------------------------------------------------------------------

    /// システム音声のキャプチャを停止する
    func stop() {
        // 非同期でキャプチャを停止
        Task {
            try? await stream?.stopCapture()
            stream = nil
            streamOutput = nil
            print("System audio capture stopped")
        }
    }

    // -------------------------------------------------------------------------
    // 音声データの処理
    // -------------------------------------------------------------------------

    /// CMSampleBufferをAVAudioPCMBufferに変換して外部に渡す
    /// - Parameter sampleBuffer: CoreMediaのサンプルバッファ
    ///
    /// 【解説】
    /// CMSampleBuffer: CoreMediaフレームワークの低レベルなデータ形式
    /// AVAudioPCMBuffer: AVFoundationのより扱いやすい音声データ形式
    /// ここでは前者を後者に変換している
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // フォーマット情報を取得
        // formatDescription: 音声のフォーマット情報（サンプルレート、チャンネル数など）
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        // AVAudioFormatを作成
        // pcmFormatFloat32: 32ビット浮動小数点形式（-1.0〜1.0の範囲）
        // interleaved: false = チャンネルごとに別々の配列に格納
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asbd.pointee.mSampleRate,
            channels: AVAudioChannelCount(asbd.pointee.mChannelsPerFrame),
            interleaved: false
        )

        guard let format = format else { return }

        // サンプル数を取得
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)

        // PCMバッファを作成
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }

        // バッファの実際のフレーム数を設定
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        // 音声データをコピー
        // CMBlockBuffer: 実際の音声データが格納されている低レベルバッファ
        if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?

            // データポインタを取得
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            // Float配列にデータをコピー
            if let dataPointer = dataPointer, let floatChannelData = pcmBuffer.floatChannelData {
                // 生データをFloat型として解釈
                let floatData = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: length / MemoryLayout<Float>.size)
                let channelCount = Int(format.channelCount)
                let frameCountInt = Int(frameCount)

                // 各チャンネル、各フレームのデータをコピー
                for channel in 0..<channelCount {
                    for frame in 0..<frameCountInt {
                        if channel * frameCountInt + frame < length / MemoryLayout<Float>.size {
                            floatChannelData[channel][frame] = floatData[channel * frameCountInt + frame]
                        }
                    }
                }
            }
        }

        // コールバックを呼び出して外部に音声データを渡す
        audioDataHandler?(pcmBuffer)
    }
}

// =============================================================================
// StreamOutput - ストリームからの出力を処理するクラス
// =============================================================================
// SCStreamOutput: ストリームからのデータを受け取るプロトコル
// SCStreamDelegate: ストリームのイベント（エラーなど）を受け取るプロトコル
// =============================================================================

private class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {

    /// 音声データを受け取った時に呼ばれるコールバック
    var audioHandler: ((CMSampleBuffer) -> Void)?

    /// ストリームからデータが出力された時に呼ばれる
    /// - Parameters:
    ///   - stream: データを出力したストリーム
    ///   - sampleBuffer: 出力されたデータ
    ///   - type: データの種類（音声、映像、マイク）
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .audio:
            // 音声データの場合、コールバックを呼び出す
            audioHandler?(sampleBuffer)
        case .screen:
            // 映像データは無視（音声キャプチャのみ使用）
            break
        @unknown default:
            // マイクデータや将来追加される可能性のある種類は無視
            break
        }
    }

    /// ストリームがエラーで停止した時に呼ばれる
    /// - Parameters:
    ///   - stream: 停止したストリーム
    ///   - error: 発生したエラー
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error.localizedDescription)")
    }
}

// =============================================================================
// CaptureError - キャプチャ関連のエラー定義
// =============================================================================
// LocalizedError: ユーザーに表示するエラーメッセージを提供するプロトコル
// =============================================================================

enum CaptureError: LocalizedError {
    /// 画面収録の権限がない
    case permissionDenied
    /// ディスプレイが見つからない
    case noDisplayFound
    /// 設定に失敗
    case configurationFailed

    /// エラーメッセージを返す（ユーザーに表示される）
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "画面録画の権限が必要です。システム設定 > プライバシーとセキュリティ > 画面収録 で許可してください。"
        case .noDisplayFound:
            return "ディスプレイが見つかりませんでした。"
        case .configurationFailed:
            return "オーディオキャプチャの設定に失敗しました。"
        }
    }
}
