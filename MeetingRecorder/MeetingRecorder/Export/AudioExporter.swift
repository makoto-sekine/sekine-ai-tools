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

    /// 録音ファイルを保存するフォルダ
    private let outputFolder: URL

    /// 録音中の音声ファイル
    /// AVAudioFile: 音声ファイルを読み書きするためのクラス
    private var audioFile: AVAudioFile?

    /// 一時ファイルのURL（録音中はここに書き込む）
    private var tempFileURL: URL?

    /// 複数スレッドからの同時アクセスを防ぐためのロック
    private let lock = NSLock()

    /// 出力する音声のフォーマット
    private let outputFormat: AVAudioFormat

    // -------------------------------------------------------------------------
    // 初期化
    // -------------------------------------------------------------------------

    /// 初期化処理
    /// - Parameter outputFolder: 録音ファイルを保存するフォルダ
    init(outputFolder: URL) {
        self.outputFolder = outputFolder

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
    /// - Parameter filename: 保存するファイル名（拡張子なし）
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

        // ファイル形式を変換
        let finalURL: URL?

        if isFFmpegAvailable() {
            // ffmpegがあればMP3に変換（高圧縮・高互換性）
            finalURL = await convertToMP3(inputURL: tempURL, filename: filename)
        } else {
            // ffmpegがなければM4Aに変換（Appleの標準形式）
            finalURL = await convertToM4A(inputURL: tempURL, filename: filename)
        }

        // 一時ファイルを削除
        try? FileManager.default.removeItem(at: tempURL)

        return finalURL
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
    /// - Returns: 変換後のファイルURL（失敗した場合はnil）
    private func convertToMP3(inputURL: URL, filename: String) async -> URL? {
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
                return await convertToM4A(inputURL: inputURL, filename: filename)
            }
        } catch {
            print("FFmpeg error: \(error)")
            // エラーの場合はM4Aにフォールバック
            return await convertToM4A(inputURL: inputURL, filename: filename)
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
    /// - Returns: 変換後のファイルURL（失敗した場合はnil）
    private func convertToM4A(inputURL: URL, filename: String) async -> URL? {
        let outputURL = outputFolder.appendingPathComponent("\(filename).m4a")

        // 既存ファイルがあれば削除
        try? FileManager.default.removeItem(at: outputURL)

        // AVAsset: 音声ファイルを表すクラス
        let asset = AVAsset(url: inputURL)

        do {
            // 音声トラックを取得
            guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                print("No audio track found")
                return copyAsWAV(inputURL: inputURL, filename: filename)
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
                return copyAsWAV(inputURL: inputURL, filename: filename)
            }

        } catch {
            print("M4A conversion error: \(error)")
            return copyAsWAV(inputURL: inputURL, filename: filename)
        }
    }

    // -------------------------------------------------------------------------
    // WAVとしてコピー（フォールバック）
    // -------------------------------------------------------------------------

    /// 変換に失敗した場合、WAVファイルとしてそのままコピーする
    /// - Parameters:
    ///   - inputURL: 入力ファイル（WAV）
    ///   - filename: 出力ファイル名（拡張子なし）
    /// - Returns: コピーされたファイルURL（失敗した場合はnil）
    private func copyAsWAV(inputURL: URL, filename: String) -> URL? {
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
