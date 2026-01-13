import Foundation

// =============================================================================
// PostProcessor - 録音後の文字起こし・要約処理を行うクラス
// =============================================================================
// このクラスは録音終了後に以下の処理を実行します：
// 1. whisperコマンドを使用した音声の文字起こし
// 2. codex execコマンドを使用したマークダウン形式の要約生成
//
// 【前提条件】
// - whisper: ホストマシンにインストール済み
// - codex: ホストマシンにインストール済み（サブスクリプションでログイン済み）
// =============================================================================

class PostProcessor {

    // -------------------------------------------------------------------------
    // エラー定義
    // -------------------------------------------------------------------------

    /// 後処理で発生するエラー
    enum PostProcessingError: LocalizedError {
        case whisperNotFound
        case codexNotFound
        case transcriptionFailed(String)
        case summaryFailed(String)
        case fileReadFailed

        var errorDescription: String? {
            switch self {
            case .whisperNotFound:
                return "whisperコマンドが見つかりません。インストールを確認してください。"
            case .codexNotFound:
                return "codexコマンドが見つかりません。インストールを確認してください。"
            case .transcriptionFailed(let message):
                return "文字起こしに失敗しました: \(message)"
            case .summaryFailed(let message):
                return "要約に失敗しました: \(message)"
            case .fileReadFailed:
                return "文字起こしファイルの読み込みに失敗しました。"
            }
        }
    }

    // -------------------------------------------------------------------------
    // 結果構造体
    // -------------------------------------------------------------------------

    /// 後処理の結果
    struct PostProcessingResult {
        /// 文字起こしファイルのURL（成功時）
        let transcriptURL: URL?

        /// 要約ファイルのURL（成功時）
        let summaryURL: URL?

        /// 文字起こしエラー（失敗時）
        let transcriptionError: Error?

        /// 要約エラー（失敗時）
        let summaryError: Error?

        /// 処理が成功したかどうか
        var isSuccess: Bool {
            return transcriptionError == nil && summaryError == nil
        }
    }

    // -------------------------------------------------------------------------
    // コマンドパスの検索
    // -------------------------------------------------------------------------

    /// whisperコマンドのパスを検索
    private func findWhisperPath() -> String? {
        let possiblePaths = [
            "/usr/local/bin/whisper",
            "/opt/homebrew/bin/whisper",
            "\(NSHomeDirectory())/.local/bin/whisper",
            "/usr/bin/whisper"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // whichコマンドで検索
        return findCommandPath("whisper")
    }

    /// codexコマンドのパスを検索
    private func findCodexPath() -> String? {
        let possiblePaths = [
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex",
            "/usr/bin/codex"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // whichコマンドで検索
        return findCommandPath("codex")
    }

    /// whichコマンドを使ってコマンドのパスを検索
    private func findCommandPath(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            print("Failed to find \(command): \(error)")
        }

        return nil
    }

    // -------------------------------------------------------------------------
    // メイン処理
    // -------------------------------------------------------------------------

    /// 音声ファイルに対して後処理を実行
    /// - Parameter audioURL: 処理対象の音声ファイルURL
    /// - Returns: 処理結果
    func process(audioURL: URL) async -> PostProcessingResult {
        let settings = PostProcessingSettings.shared

        // 文字起こしが無効の場合は何もしない
        guard settings.isTranscriptionEnabled else {
            return PostProcessingResult(
                transcriptURL: nil,
                summaryURL: nil,
                transcriptionError: nil,
                summaryError: nil
            )
        }

        // 文字起こしを実行
        var transcriptURL: URL?
        var transcriptionError: Error?

        do {
            transcriptURL = try await transcribe(audioURL: audioURL)
            print("Transcription completed: \(transcriptURL?.path ?? "nil")")
        } catch {
            transcriptionError = error
            print("Transcription failed: \(error)")
        }

        // 文字起こしが失敗した場合、要約もスキップ
        guard transcriptionError == nil, let transcriptPath = transcriptURL else {
            return PostProcessingResult(
                transcriptURL: transcriptURL,
                summaryURL: nil,
                transcriptionError: transcriptionError,
                summaryError: nil
            )
        }

        // 要約が無効の場合は文字起こし結果のみ返す
        guard settings.isSummaryEnabled else {
            return PostProcessingResult(
                transcriptURL: transcriptPath,
                summaryURL: nil,
                transcriptionError: nil,
                summaryError: nil
            )
        }

        // 要約を実行
        var summaryURL: URL?
        var summaryError: Error?

        do {
            summaryURL = try await summarize(transcriptURL: transcriptPath, audioURL: audioURL)
            print("Summary completed: \(summaryURL?.path ?? "nil")")
        } catch {
            summaryError = error
            print("Summary failed: \(error)")
        }

        return PostProcessingResult(
            transcriptURL: transcriptPath,
            summaryURL: summaryURL,
            transcriptionError: nil,
            summaryError: summaryError
        )
    }

    // -------------------------------------------------------------------------
    // 文字起こし処理
    // -------------------------------------------------------------------------

    /// whisperコマンドを使用して音声を文字起こし
    /// - Parameter audioURL: 処理対象の音声ファイルURL
    /// - Returns: 生成された文字起こしファイルのURL
    private func transcribe(audioURL: URL) async throws -> URL {
        guard let whisperPath = findWhisperPath() else {
            throw PostProcessingError.whisperNotFound
        }

        let outputDir = audioURL.deletingLastPathComponent().path
        let baseName = audioURL.deletingPathExtension().lastPathComponent

        // whisperコマンドを実行
        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        process.arguments = [
            audioURL.path,
            "--model", "small",
            "--language", "Japanese",
            "--output_format", "txt",
            "--output_dir", outputDir
        ]

        // 環境変数を設定（PATHを引き継ぐ）
        var environment = ProcessInfo.processInfo.environment
        if let path = environment["PATH"] {
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(path)"
        }
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw PostProcessingError.transcriptionFailed(errorMessage)
            }

            // whisperは自動的に .txt ファイルを生成する
            let transcriptURL = audioURL.deletingLastPathComponent()
                .appendingPathComponent("\(baseName).txt")

            // ファイルが生成されたか確認
            if !FileManager.default.fileExists(atPath: transcriptURL.path) {
                throw PostProcessingError.transcriptionFailed("出力ファイルが見つかりません")
            }

            return transcriptURL

        } catch let error as PostProcessingError {
            throw error
        } catch {
            throw PostProcessingError.transcriptionFailed(error.localizedDescription)
        }
    }

    // -------------------------------------------------------------------------
    // 要約処理
    // -------------------------------------------------------------------------

    /// codex execコマンドを使用して文字起こしを要約
    /// - Parameters:
    ///   - transcriptURL: 文字起こしファイルのURL
    ///   - audioURL: 元の音声ファイルURL（出力ファイル名の生成に使用）
    /// - Returns: 生成された要約ファイルのURL
    private func summarize(transcriptURL: URL, audioURL: URL) async throws -> URL {
        guard let codexPath = findCodexPath() else {
            throw PostProcessingError.codexNotFound
        }

        // 文字起こしファイルを読み込む
        guard let transcriptContent = try? String(contentsOf: transcriptURL, encoding: .utf8) else {
            throw PostProcessingError.fileReadFailed
        }

        // 出力ファイルのパスを生成
        let baseName = audioURL.deletingPathExtension().lastPathComponent
        let summaryURL = audioURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_summary.md")

        // プロンプトを作成
        let prompt = """
以下の会議の文字起こしをマークダウン形式で要約してください。

## 出力形式
以下の形式で要約を作成してください：

# 会議要約

## 概要
（会議の概要を1-2文で）

## 参加者（推定）
- （発言から推定される参加者）

## 議題
1. （議題1）
2. （議題2）
...

## 決定事項
- （決定事項1）
- （決定事項2）
...

## アクションアイテム
- [ ] （担当者）: （タスク内容）
- [ ] （担当者）: （タスク内容）
...

## 次回の予定
（あれば記載）

---

## 文字起こし内容

\(transcriptContent)
"""

        // codex execコマンドを実行
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["exec", prompt]

        // 環境変数を設定
        var environment = ProcessInfo.processInfo.environment
        if let path = environment["PATH"] {
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(path)"
        }
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw PostProcessingError.summaryFailed(errorMessage)
            }

            // codex execの出力を取得
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let summaryContent = String(data: outputData, encoding: .utf8),
                  !summaryContent.isEmpty else {
                throw PostProcessingError.summaryFailed("要約の出力が空です")
            }

            // 要約をファイルに保存
            try summaryContent.write(to: summaryURL, atomically: true, encoding: .utf8)

            return summaryURL

        } catch let error as PostProcessingError {
            throw error
        } catch {
            throw PostProcessingError.summaryFailed(error.localizedDescription)
        }
    }
}
