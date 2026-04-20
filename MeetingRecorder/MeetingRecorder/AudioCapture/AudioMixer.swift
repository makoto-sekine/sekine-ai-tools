import Foundation
import AVFoundation
import Accelerate

// =============================================================================
// AudioMixer - 複数の音声ソースをミックスするクラス
// =============================================================================
// このクラスはシステム音声とマイク音声を受け取り、
// 1つの音声ストリームに合成（ミックス）します。
//
// 【音声ミキシングの仕組み】
// - 各ソースからの音声データを一時バッファに蓄積
// - 定期的に（100msごと）両方のバッファから同じ量のサンプルを取り出す
// - 2つの音声を足し合わせて1つの音声にする
// - ミックスした音声を出力ハンドラーに渡す
// =============================================================================

class AudioMixer {

    // -------------------------------------------------------------------------
    // プロパティ
    // -------------------------------------------------------------------------

    /// 出力する音声のフォーマット
    /// 48kHz, モノラル, 32ビット浮動小数点
    private let outputFormat: AVAudioFormat

    /// 複数スレッドからの同時アクセスを防ぐためのロック
    /// NSLock: 排他制御（同時に1つのスレッドだけがアクセスできるようにする）
    private let lock = NSLock()

    /// バッファの最大サイズ（サンプル数）
    /// 48kHz × 10秒 = 480,000サンプル
    /// これを超えると古いデータを破棄してメモリリークを防ぐ
    private let maxBufferSize = 480000

    /// システム音声を一時的に蓄積するバッファ
    /// Float型の配列で、-1.0〜1.0の範囲の音声サンプルを格納
    private var systemBuffer: [Float] = []

    /// マイク音声を一時的に蓄積するバッファ
    private var micBuffer: [Float] = []

    /// ミキシングを行う間隔（秒）
    /// 0.1秒 = 100ミリ秒ごとにミキシング処理を実行
    private let mixInterval: TimeInterval = 0.1

    /// ミキシング処理を定期的に実行するタイマー
    private var mixTimer: Timer?

    /// ミックスした音声データを外部に渡すためのコールバック
    var outputHandler: ((AVAudioPCMBuffer) -> Void)?

    /// システム音声の音量（0.0〜1.0）
    /// 1.0 = 100%の音量
    var systemVolume: Float = 1.0

    /// マイク音声の音量（0.0〜1.0）
    var microphoneVolume: Float = 1.0

    // -------------------------------------------------------------------------
    // 初期化と終了処理
    // -------------------------------------------------------------------------

    /// 初期化処理
    init() {
        // 出力フォーマットを設定
        // sampleRate: 48000 = 48kHz（入力と同じにして速度劣化を防止）
        // channels: 1 = モノラル（ファイルサイズ半減）
        // interleaved: false = 非インターリーブ
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: false
        )!

        // ミキシング処理を開始
        startMixing()
    }

    /// デイニシャライザ（オブジェクトが解放される時に呼ばれる）
    /// タイマーを停止してリソースをクリーンアップ
    deinit {
        stopMixing()
    }

    // -------------------------------------------------------------------------
    // 音声データの追加
    // -------------------------------------------------------------------------

    /// システム音声データをバッファに追加する
    /// - Parameter buffer: システムからキャプチャした音声データ
    func addSystemAudio(_ buffer: AVAudioPCMBuffer) {
        // 音声データ（Float配列）を取得
        guard let floatData = buffer.floatChannelData else { return }

        // ロックを取得（他のスレッドからの同時アクセスを防ぐ）
        lock.lock()
        defer { lock.unlock() }  // deferはスコープを抜ける時に必ず実行される

        let frameCount = Int(buffer.frameLength)  // サンプル数
        let channelCount = Int(buffer.format.channelCount)  // チャンネル数

        // 複数チャンネルをモノラルにミックスダウン
        // ステレオ（2ch）の場合、左右の平均値を取る
        for frame in 0..<frameCount {
            var sample: Float = 0

            // 全チャンネルのサンプル値を合計
            for channel in 0..<channelCount {
                sample += floatData[channel][frame]
            }

            // チャンネル数で割って平均を取る
            sample /= Float(channelCount)

            // 音量を適用
            sample *= systemVolume

            // バッファに追加
            systemBuffer.append(sample)
        }

        // バッファサイズ制限チェック（メモリリーク防止）
        if systemBuffer.count > maxBufferSize {
            let excess = systemBuffer.count - maxBufferSize
            systemBuffer.removeFirst(excess)
            print("Warning: System audio buffer overflow (\(systemBuffer.count) samples), dropped \(excess) old samples")
        }
    }

    /// マイク音声データをバッファに追加する
    /// - Parameter buffer: マイクからキャプチャした音声データ
    func addMicrophoneAudio(_ buffer: AVAudioPCMBuffer) {
        // 音声データ（Float配列）を取得
        guard let floatData = buffer.floatChannelData else { return }

        // ロックを取得
        lock.lock()
        defer { lock.unlock() }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        // 複数チャンネルをモノラルにミックスダウン
        for frame in 0..<frameCount {
            var sample: Float = 0

            for channel in 0..<channelCount {
                sample += floatData[channel][frame]
            }

            sample /= Float(channelCount)
            sample *= microphoneVolume
            micBuffer.append(sample)
        }

        // バッファサイズ制限チェック（メモリリーク防止）
        if micBuffer.count > maxBufferSize {
            let excess = micBuffer.count - maxBufferSize
            micBuffer.removeFirst(excess)
            print("Warning: Microphone audio buffer overflow (\(micBuffer.count) samples), dropped \(excess) old samples")
        }
    }

    // -------------------------------------------------------------------------
    // ミキシング処理
    // -------------------------------------------------------------------------

    /// ミキシング用タイマーを開始する
    private func startMixing() {
        // タイマー開始処理をラップ
        let startOnMain = { [weak self] in
            guard let self = self else { return }

            // 定期的にprocessMix()を呼び出すタイマーを作成
            self.mixTimer = Timer.scheduledTimer(withTimeInterval: self.mixInterval, repeats: true) { [weak self] _ in
                self?.processMix()
            }
        }

        // タイマーはメインスレッドで動かす必要がある
        if Thread.isMainThread {
            startOnMain()
        } else {
            DispatchQueue.main.async {
                startOnMain()
            }
        }
    }

    /// ミキシング用タイマーを停止する
    private func stopMixing() {
        mixTimer?.invalidate()
        mixTimer = nil
    }

    /// 蓄積された音声データをミックスして出力する
    /// このメソッドはタイマーによって定期的に呼び出される
    private func processMix() {
        lock.lock()

        // 両方のバッファから処理できるサンプル数を決定
        // 短い方に合わせる（同期を取るため）
        let samplesToProcess = min(systemBuffer.count, micBuffer.count)

        guard samplesToProcess > 0 else {
            // どちらか一方のバッファにしかデータがない場合
            let maxSamples = max(systemBuffer.count, micBuffer.count)

            guard maxSamples > 0 else {
                // 両方空の場合は何もしない
                lock.unlock()
                return
            }

            // 片方のデータだけで出力を作成
            var outputSamples = [Float](repeating: 0, count: maxSamples)

            if !systemBuffer.isEmpty {
                // システム音声のみ
                for i in 0..<systemBuffer.count {
                    outputSamples[i] += systemBuffer[i]
                }
                systemBuffer.removeAll()
            }

            if !micBuffer.isEmpty {
                // マイク音声のみ
                for i in 0..<micBuffer.count {
                    outputSamples[i] += micBuffer[i]
                }
                micBuffer.removeAll()
            }

            lock.unlock()
            createAndOutputBuffer(from: outputSamples)
            return
        }

        // 両方のバッファをミックス
        var outputSamples = [Float](repeating: 0, count: samplesToProcess)

        for i in 0..<samplesToProcess {
            // 2つの音声を単純に足し合わせる
            let mixed = systemBuffer[i] + micBuffer[i]

            // クリッピング処理（-1.0〜1.0の範囲に収める）
            // 音が大きすぎると歪むため
            outputSamples[i] = max(-1.0, min(1.0, mixed))
        }

        // 処理したサンプルをバッファから削除
        systemBuffer.removeFirst(samplesToProcess)
        micBuffer.removeFirst(samplesToProcess)

        lock.unlock()

        // ミックスした音声を出力
        createAndOutputBuffer(from: outputSamples)
    }

    /// Float配列からAVAudioPCMBufferを作成して出力する
    /// - Parameter samples: ミックス済みの音声サンプル配列
    private func createAndOutputBuffer(from samples: [Float]) {
        let frameCount = AVAudioFrameCount(samples.count)

        // PCMバッファを作成
        guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return
        }

        buffer.frameLength = frameCount

        // モノラル出力（1チャンネルのみ）
        if let floatData = buffer.floatChannelData {
            for i in 0..<samples.count {
                floatData[0][i] = samples[i]
            }
        }

        // コールバックを呼び出して外部に渡す
        outputHandler?(buffer)
    }
}
