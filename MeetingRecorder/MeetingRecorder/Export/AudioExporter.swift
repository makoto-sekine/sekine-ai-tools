import Foundation
import AVFoundation

// =============================================================================
// AudioExporter - 音声データをファイルに書き出すクラス
// =============================================================================
// このクラスはミックスされた音声データを受け取り、
// ファイルとして保存します。
//
// 【出力設定】
// - フォーマット: M4A (AAC) / 48kHz / モノラル / 64kbps
// - ファイルサイズ目安: 約480KB/分（8KB/秒）
//
// 【ファイル形式の優先順位】
// 1. MP3（ffmpegがインストールされている場合）
// 2. M4A（AVAssetWriterで64kbpsに圧縮）
// 3. WAV（変換に失敗した場合のフォールバック）
// =============================================================================

class AudioExporter {

    // -------------------------------------------------------------------------
    // プロパティ
    // -------------------------------------------------------------------------

    /// 録音中の音声ファイル
    /// AVAudioFile: 音声ファイルを読み書きするためのクラス
    private var audioFile: AVAudioFile?

    /// 一時ファイルのURL（録音中はここに書き込む）
    private var tempFileURL: URL?

    /// 複数スレッドからの同時アクセスを防ぐためのロック
    private let lock = NSLock()

    /// 出力する音声のフォーマット
    private let outputFormat: AVAudioFormat

    /// 無音カット機能の有効/無効
    var isSilenceRemovalEnabled: Bool = true

    /// 無音と判定するRMSしきい値（0.01 = 約-40dB）
    private let silenceThreshold: Float = 0.01

    /// この秒数以上の無音をカット対象とする（1.0秒）
    private let minimumSilenceDuration: TimeInterval = 1.0

    /// カット時に残す余白（前後に0.2秒ずつ）
    private let silencePadding: TimeInterval = 0.2

    // -------------------------------------------------------------------------
    // 初期化
    // -------------------------------------------------------------------------

    /// 初期化処理
    init() {
        // 出力フォーマットを設定
        // WAV形式（非圧縮）で一時保存し、後でM4Aに変換する
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,  // 32ビット浮動小数点
            sampleRate: 48000,                // 48kHz（入力と同じにして速度劣化を防止）
            channels: 1,                      // モノラル
            interleaved: false                // 非インターリーブ
        )!
    }

    // -------------------------------------------------------------------------
    // 録音の開始
    // -------------------------------------------------------------------------

    /// 録音を開始する（一時ファイルへの書き込みを開始）
    /// - Throws: ファイル作成に失敗した場合にエラーをスロー
    func startRecording() throws {
        lock.lock()
        defer { lock.unlock() }

        // 一時ディレクトリにファイルを作成
        // 録音中は一時ファイルに書き込み、終了後に変換してから正式な場所に保存
        let tempDir = FileManager.default.temporaryDirectory
        let tempFilename = "recording_\(UUID().uuidString).wav"
        tempFileURL = tempDir.appendingPathComponent(tempFilename)

        guard let tempURL = tempFileURL else {
            throw ExportError.fileCreationFailed
        }

        // 音声ファイルを作成（書き込みモード）
        audioFile = try AVAudioFile(
            forWriting: tempURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        print("Started recording to temp file: \(tempURL.path)")
    }

    // -------------------------------------------------------------------------
    // 音声データの書き込み
    // -------------------------------------------------------------------------

    /// 音声データをファイルに追記する
    /// - Parameter buffer: 書き込む音声データ
    func appendAudio(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard let audioFile = audioFile else { return }

        do {
            // バッファの内容をファイルに書き込む
            try audioFile.write(from: buffer)
        } catch {
            print("Error writing audio buffer: \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // 録音の停止とファイル変換
    // -------------------------------------------------------------------------

    /// 録音を停止し、ファイルを変換して保存する
    /// - Parameter filename: 保存するファイル名（拡張子なし）= フォルダ名
    /// - Returns: 保存されたファイルのURL（失敗した場合はnil）
    func stopRecording(filename: String) async -> URL? {
        lock.lock()

        guard let tempURL = tempFileURL else {
            lock.unlock()
            return nil
        }

        // 音声ファイルを閉じる（nilを代入することで自動的にファイルが閉じられる）
        audioFile = nil
        tempFileURL = nil

        lock.unlock()

        // ID用のフォルダを作成（QueueManagerから取得）
        let itemFolder = QueueManager.shared.createItemFolder(for: filename)

        // 無音カット処理（有効な場合のみ）
        let processedURL: URL
        if isSilenceRemovalEnabled {
            if let silenceRemovedURL = await removeSilence(from: tempURL) {
                processedURL = silenceRemovedURL
                // 元のtempURLを削除
                try? FileManager.default.removeItem(at: tempURL)
            } else {
                // 無音カット失敗時は元のファイルを使用
                print("Silence removal failed, using original file")
                processedURL = tempURL
            }
        } else {
            processedURL = tempURL
        }

        // ファイル形式を変換（フォルダ内に出力）
        let finalURL: URL?

        if isFFmpegAvailable() {
            // ffmpegがあればMP3に変換（高圧縮・高互換性）
            finalURL = await convertToMP3(inputURL: processedURL, filename: filename, outputFolder: itemFolder)
        } else {
            // ffmpegがなければM4Aに変換（Appleの標準形式）
            finalURL = await convertToM4A(inputURL: processedURL, filename: filename, outputFolder: itemFolder)
        }

        // 処理済みファイルを削除
        try? FileManager.default.removeItem(at: processedURL)

        return finalURL
    }

    // -------------------------------------------------------------------------
    // 無音カット処理
    // -------------------------------------------------------------------------

    /// 音声ファイルから無音部分をカットする
    /// - Parameter inputURL: 入力ファイル（WAV）
    /// - Returns: 無音カット後のファイルURL（失敗した場合はnil）
    private func removeSilence(from inputURL: URL) async -> URL? {
        do {
            // 入力ファイルを読み込む
            let inputFile = try AVAudioFile(forReading: inputURL)
            let format = inputFile.processingFormat
            let sampleRate = format.sampleRate

            // ウィンドウサイズ（100ms分のサンプル数）
            let windowSize = Int(sampleRate * 0.1)

            // 余白サンプル数
            let paddingSamples = Int(sampleRate * silencePadding)

            // 最小無音サンプル数
            let minimumSilenceSamples = Int(sampleRate * minimumSilenceDuration)

            // ファイル全体を読み込む
            let frameCount = AVAudioFrameCount(inputFile.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return nil
            }

            try inputFile.read(into: buffer)
            buffer.frameLength = frameCount

            guard let floatData = buffer.floatChannelData else {
                return nil
            }

            // 無音区間を検出
            var isInSilence = false
            var silenceStartFrame = 0
            var silenceRanges: [(start: Int, end: Int)] = []

            let totalFrames = Int(buffer.frameLength)
            let channelCount = Int(format.channelCount)

            for windowStart in stride(from: 0, to: totalFrames, by: windowSize) {
                let windowEnd = min(windowStart + windowSize, totalFrames)
                let windowFrames = windowEnd - windowStart

                // ウィンドウ内のRMSを計算
                var sumSquares: Float = 0
                for channel in 0..<channelCount {
                    for frame in windowStart..<windowEnd {
                        let sample = floatData[channel][frame]
                        sumSquares += sample * sample
                    }
                }

                let rms = sqrt(sumSquares / Float(windowFrames * channelCount))

                // 無音判定
                if rms < silenceThreshold {
                    if !isInSilence {
                        // 無音開始
                        isInSilence = true
                        silenceStartFrame = windowStart
                    }
                } else {
                    if isInSilence {
                        // 無音終了
                        let silenceDuration = windowStart - silenceStartFrame

                        // 最小無音時間以上の場合のみ記録
                        if silenceDuration >= minimumSilenceSamples {
                            silenceRanges.append((start: silenceStartFrame, end: windowStart))
                        }

                        isInSilence = false
                    }
                }
            }

            // 最後まで無音だった場合
            if isInSilence {
                let silenceDuration = totalFrames - silenceStartFrame
                if silenceDuration >= minimumSilenceSamples {
                    silenceRanges.append((start: silenceStartFrame, end: totalFrames))
                }
            }

            print("Detected \(silenceRanges.count) silence regions")

            // 無音区間がない場合は元のファイルを返す
            guard !silenceRanges.isEmpty else {
                print("No silence regions to remove")
                return inputURL
            }

            // 出力ファイルを作成
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("silence_removed_\(UUID().uuidString).wav")

            let outputFile = try AVAudioFile(
                forWriting: outputURL,
                settings: format.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )

            // 無音区間以外を出力ファイルに書き込む
            var currentFrame = 0

            for silenceRange in silenceRanges {
                // 余白を考慮した無音区間の開始・終了
                let silenceStart = max(0, silenceRange.start - paddingSamples)
                let silenceEnd = min(totalFrames, silenceRange.end + paddingSamples)

                // 無音区間前の音声部分を書き込む
                if currentFrame < silenceStart {
                    let segmentLength = silenceStart - currentFrame

                    if let segmentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(segmentLength)) {
                        segmentBuffer.frameLength = AVAudioFrameCount(segmentLength)

                        // データをコピー
                        if let segmentFloatData = segmentBuffer.floatChannelData {
                            for channel in 0..<channelCount {
                                for i in 0..<segmentLength {
                                    segmentFloatData[channel][i] = floatData[channel][currentFrame + i]
                                }
                            }
                        }

                        try outputFile.write(from: segmentBuffer)
                    }
                }

                currentFrame = silenceEnd
            }

            // 最後の無音区間以降の音声を書き込む
            if currentFrame < totalFrames {
                let segmentLength = totalFrames - currentFrame

                if let segmentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(segmentLength)) {
                    segmentBuffer.frameLength = AVAudioFrameCount(segmentLength)

                    if let segmentFloatData = segmentBuffer.floatChannelData {
                        for channel in 0..<channelCount {
                            for i in 0..<segmentLength {
                                segmentFloatData[channel][i] = floatData[channel][currentFrame + i]
                            }
                        }
                    }

                    try outputFile.write(from: segmentBuffer)
                }
            }

            let originalDuration = Double(totalFrames) / sampleRate
            let newDuration = Double(outputFile.length) / sampleRate
            let removedDuration = originalDuration - newDuration

            print("Silence removal complete: removed \(String(format: "%.1f", removedDuration))s from \(String(format: "%.1f", originalDuration))s")

            return outputURL

        } catch {
            print("Error removing silence: \(error)")
            return nil
        }
    }

    // -------------------------------------------------------------------------
    // ffmpegの確認
    // -------------------------------------------------------------------------

    /// ffmpegがインストールされているか確認する
    /// - Returns: ffmpegが利用可能ならtrue
    private func isFFmpegAvailable() -> Bool {
        // whichコマンドでffmpegを探す
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            // 終了ステータスが0ならffmpegが見つかった
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // -------------------------------------------------------------------------
    // MP3への変換
    // -------------------------------------------------------------------------

    /// WAVファイルをMP3に変換する
    /// - Parameters:
    ///   - inputURL: 入力ファイル（WAV）
    ///   - filename: 出力ファイル名（拡張子なし）
    ///   - outputFolder: 出力先フォルダ
    /// - Returns: 変換後のファイルURL（失敗した場合はnil）
    private func convertToMP3(inputURL: URL, filename: String, outputFolder: URL) async -> URL? {
        let outputURL = outputFolder.appendingPathComponent("\(filename).mp3")

        // 既存ファイルがあれば削除
        try? FileManager.default.removeItem(at: outputURL)

        // ffmpegプロセスを作成
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ffmpeg")

        // ffmpegの一般的なインストール場所をチェック
        let ffmpegPaths = [
            "/usr/local/bin/ffmpeg",      // Homebrewなど
            "/opt/homebrew/bin/ffmpeg",   // Apple Silicon Mac
            "/usr/bin/ffmpeg"             // システム
        ]

        for path in ffmpegPaths {
            if FileManager.default.fileExists(atPath: path) {
                process.executableURL = URL(fileURLWithPath: path)
                break
            }
        }

        // ffmpegのオプション設定
        process.arguments = [
            "-i", inputURL.path,      // 入力ファイル
            "-codec:a", "libmp3lame", // MP3コーデック
            "-b:a", "192k",           // ビットレート192kbps
            "-y",                     // 既存ファイルを上書き
            outputURL.path            // 出力ファイル
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                print("Converted to MP3: \(outputURL.path)")
                return outputURL
            } else {
                print("FFmpeg conversion failed")
                // 失敗した場合はM4Aにフォールバック
                return await convertToM4A(inputURL: inputURL, filename: filename, outputFolder: outputFolder)
            }
        } catch {
            print("FFmpeg error: \(error)")
            // エラーの場合はM4Aにフォールバック
            return await convertToM4A(inputURL: inputURL, filename: filename, outputFolder: outputFolder)
        }
    }

    // -------------------------------------------------------------------------
    // M4Aへの変換
    // -------------------------------------------------------------------------

    /// WAVファイルをM4A（AAC）に変換する
    /// AVAssetWriterを使用して低ビットレートで圧縮
    /// - Parameters:
    ///   - inputURL: 入力ファイル（WAV）
    ///   - filename: 出力ファイル名（拡張子なし）
    ///   - outputFolder: 出力先フォルダ
    /// - Returns: 変換後のファイルURL（失敗した場合はnil）
    private func convertToM4A(inputURL: URL, filename: String, outputFolder: URL) async -> URL? {
        let outputURL = outputFolder.appendingPathComponent("\(filename).m4a")

        // 既存ファイルがあれば削除
        try? FileManager.default.removeItem(at: outputURL)

        // AVAsset: 音声ファイルを表すクラス
        let asset = AVAsset(url: inputURL)

        do {
            // 音声トラックを取得
            guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                print("No audio track found")
                return copyAsWAV(inputURL: inputURL, filename: filename, outputFolder: outputFolder)
            }

            // AVAssetReader: 音声ファイルを読み込むためのクラス
            let assetReader = try AVAssetReader(asset: asset)

            // 読み込み設定（PCM形式で読み込む）
            let readerOutputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 24000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]

            let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerOutputSettings)
            assetReader.add(readerOutput)

            // AVAssetWriter: 音声ファイルを書き出すためのクラス
            let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)

            // AAC出力設定（64kbps、モノラル、24kHz）
            let writerInputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 24000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000  // 64kbps（会議録音に十分な品質）
            ]

            let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerInputSettings)
            assetWriter.add(writerInput)

            // 変換開始
            assetReader.startReading()
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: .zero)

            // 音声データを読み込んで書き出す
            await withCheckedContinuation { continuation in
                let processingQueue = DispatchQueue(label: "audio.processing")

                writerInput.requestMediaDataWhenReady(on: processingQueue) {
                    while writerInput.isReadyForMoreMediaData {
                        if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                            // サンプルバッファを書き込む
                            writerInput.append(sampleBuffer)
                        } else {
                            // 読み込み完了
                            writerInput.markAsFinished()
                            continuation.resume()
                            return
                        }
                    }
                }
            }

            // 書き込み完了を待つ
            await assetWriter.finishWriting()

            if assetWriter.status == .completed {
                print("Converted to M4A (64kbps): \(outputURL.path)")
                return outputURL
            } else {
                print("M4A conversion failed: \(assetWriter.error?.localizedDescription ?? "unknown error")")
                return copyAsWAV(inputURL: inputURL, filename: filename, outputFolder: outputFolder)
            }

        } catch {
            print("M4A conversion error: \(error)")
            return copyAsWAV(inputURL: inputURL, filename: filename, outputFolder: outputFolder)
        }
    }

    // -------------------------------------------------------------------------
    // WAVとしてコピー（フォールバック）
    // -------------------------------------------------------------------------

    /// 変換に失敗した場合、WAVファイルとしてそのままコピーする
    /// - Parameters:
    ///   - inputURL: 入力ファイル（WAV）
    ///   - filename: 出力ファイル名（拡張子なし）
    ///   - outputFolder: 出力先フォルダ
    /// - Returns: コピーされたファイルURL（失敗した場合はnil）
    private func copyAsWAV(inputURL: URL, filename: String, outputFolder: URL) -> URL? {
        let outputURL = outputFolder.appendingPathComponent("\(filename).wav")

        do {
            // 既存ファイルがあれば削除
            try? FileManager.default.removeItem(at: outputURL)
            // ファイルをコピー
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            print("Saved as WAV: \(outputURL.path)")
            return outputURL
        } catch {
            print("Failed to copy WAV: \(error)")
            return nil
        }
    }
}

// =============================================================================
// ExportError - エクスポート関連のエラー定義
// =============================================================================

enum ExportError: LocalizedError {
    /// ファイル作成に失敗
    case fileCreationFailed
    /// 変換に失敗
    case conversionFailed

    /// エラーメッセージを返す
    var errorDescription: String? {
        switch self {
        case .fileCreationFailed:
            return "録音ファイルの作成に失敗しました。"
        case .conversionFailed:
            return "音声ファイルの変換に失敗しました。"
        }
    }
}
