import Foundation

// =============================================================================
// PostProcessor - 録音後の文字起こし・要約処理を行うクラス
// =============================================================================
// このクラスは録音終了後に以下の処理を実行します：
// 1. whisperコマンドを使用した音声の文字起こし
// 2. 選択されたCLI（codex / claude）を使用したマークダウン形式の要約生成
//
// 【前提条件】
// - whisper: ホストマシンにインストール済み
// - codex または claude: ホストマシンにインストール済み（ログイン済み）
// =============================================================================

class PostProcessor {

    // -------------------------------------------------------------------------
    // プロパティ
    // -------------------------------------------------------------------------

    /// 実行中のプロセスを管理（アプリ終了時にクリーンアップするため）
    private var runningProcesses: [Process] = []
    private let processLock = NSLock()

    // -------------------------------------------------------------------------
    // エラー定義
    // -------------------------------------------------------------------------

    /// 後処理で発生するエラー
    enum PostProcessingError: LocalizedError {
        case whisperNotFound
        case codexNotFound
        case claudeNotFound
        case transcriptionFailed(String)
        case summaryFailed(String)
        case fileReadFailed
        case exportDecisionFailed(String)

        var errorDescription: String? {
            switch self {
            case .whisperNotFound:
                return "whisperコマンドが見つかりません。インストールを確認してください。"
            case .codexNotFound:
                return "codexコマンドが見つかりません。インストールを確認してください。"
            case .claudeNotFound:
                return "claudeコマンドが見つかりません。インストールを確認してください。"
            case .transcriptionFailed(let message):
                return "文字起こしに失敗しました: \(message)"
            case .summaryFailed(let message):
                return "要約に失敗しました: \(message)"
            case .fileReadFailed:
                return "文字起こしファイルの読み込みに失敗しました。"
            case .exportDecisionFailed(let message):
                return "エクスポート先の判定に失敗しました: \(message)"
            }
        }
    }

    // -------------------------------------------------------------------------
    // エクスポート先情報
    // -------------------------------------------------------------------------

    /// エージェントが判定したエクスポート先
    struct ExportDestination {
        /// プロジェクトフォルダ名（Meetings 配下のフォルダ名）
        let project: String
        /// 短い会議名（ファイル名の一部に使う）
        let title: String
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
    // プロセス管理
    // -------------------------------------------------------------------------

    /// 実行中のすべてのプロセスを終了する（アプリ終了時に呼ばれる）
    func cancelAllProcesses() {
        processLock.lock()
        defer { processLock.unlock() }

        for process in runningProcesses {
            if process.isRunning {
                print("PostProcessor: Terminating process \(process.processIdentifier)")
                process.terminate()
            }
        }
        runningProcesses.removeAll()
    }

    /// プロセスを実行中リストに追加
    private func registerProcess(_ process: Process) {
        processLock.lock()
        defer { processLock.unlock() }
        runningProcesses.append(process)
    }

    /// プロセスを実行中リストから削除
    private func unregisterProcess(_ process: Process) {
        processLock.lock()
        defer { processLock.unlock() }
        runningProcesses.removeAll { $0 === process }
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
            "\(NSHomeDirectory())/.nodebrew/current/bin/codex",
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

    /// claude (Claude Code) コマンドのパスを検索
    private func findClaudePath() -> String? {
        let possiblePaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.nodebrew/current/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "\(NSHomeDirectory())/.npm-global/bin/claude",
            "\(NSHomeDirectory())/.claude/local/claude",
            "/usr/bin/claude"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // whichコマンドで検索
        return findCommandPath("claude")
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
            print("PostProcessor: transcription disabled, skipping")
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
            print("PostProcessor: transcription start for \(audioURL.path)")
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
            print("PostProcessor: summary disabled, skipping")
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
            print("PostProcessor: summary start for transcript \(transcriptPath.path)")
            let baseName = audioURL.deletingPathExtension().lastPathComponent
            summaryURL = try await summarize(transcriptURL: transcriptPath, baseName: baseName, outputFolder: nil)
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
    // 公開メソッド（キューマネージャーから使用）
    // -------------------------------------------------------------------------

    /// 文字起こしのみを実行（指定されたフォルダに出力）
    /// - Parameters:
    ///   - audioURL: 処理対象の音声ファイルURL
    ///   - outputFolder: 出力先フォルダ
    /// - Returns: 生成された文字起こしファイルのURL
    func transcribeOnly(audioURL: URL, outputFolder: URL) async throws -> URL {
        return try await transcribe(audioURL: audioURL, outputFolder: outputFolder)
    }

    /// 要約のみを実行（指定されたフォルダに出力）
    /// - Parameters:
    ///   - transcriptURL: 文字起こしファイルのURL
    ///   - baseName: ベースファイル名（拡張子なし）
    ///   - outputFolder: 出力先フォルダ
    /// - Returns: 生成された要約ファイルのURL
    func summarizeOnly(transcriptURL: URL, baseName: String, outputFolder: URL) async throws -> URL {
        return try await summarize(transcriptURL: transcriptURL, baseName: baseName, outputFolder: outputFolder)
    }

    /// 要約内容と既存プロジェクト一覧から、Obsidianへのエクスポート先を判定する
    /// - Parameters:
    ///   - summaryContent: 要約ファイルの内容
    ///   - existingProjects: `{vault}/Meetings/` 配下にある既存プロジェクトフォルダ名の一覧
    ///   - recordedDate: 会議の録音日（判定の補助情報）
    ///   - workingDirectory: エージェント実行時のカレントディレクトリ
    /// - Returns: プロジェクト名と短い会議名
    func decideExportDestination(
        summaryContent: String,
        existingProjects: [String],
        recordedDate: Date,
        workingDirectory: URL
    ) async throws -> ExportDestination {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: recordedDate)

        let projectsList: String
        if existingProjects.isEmpty {
            projectsList = "（なし）"
        } else {
            projectsList = existingProjects.map { "- \($0)" }.joined(separator: "\n")
        }

        let prompt = """
以下の会議要約を Obsidian vault のどのプロジェクトフォルダに配置するか判断してください。

## 既存のプロジェクトフォルダ一覧
\(projectsList)

## 録音日
\(dateString)

## 要約
\(summaryContent)

## 指示
- 既存プロジェクトのいずれかに該当するなら、そのフォルダ名を**一字一句そのまま**使ってください。
- 該当するものがなく、かつ要約から特定のプロジェクトを明確に判定できる場合のみ、新しいプロジェクト名を提案してください。フォルダ名として使えるよう簡潔にしてください。
- どのプロジェクトに属するか判断が難しい・自信がない場合は、必ず `"Others"` を使ってください。新規プロジェクトを乱発しないでください。
- 会議名は短く（目安として20文字以内）、ファイル名として使えるよう記号（/ \\ : * ? " < > |）を避けてください。
- 出力は**JSON1行のみ**。前置き・説明文・コードフェンス（```）は一切出力しないでください。

## 出力形式
{"project":"<プロジェクトフォルダ名>","title":"<短い会議名>"}
"""

        let rawOutput = try runLLM(prompt: prompt, workingDirectory: workingDirectory)

        guard let jsonString = extractJSONObject(from: rawOutput),
              let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let project = (obj["project"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !project.isEmpty, !title.isEmpty else {
            throw PostProcessingError.exportDecisionFailed("エージェントの応答を解釈できませんでした: \(rawOutput.prefix(200))")
        }

        return ExportDestination(project: project, title: title)
    }

    /// 出力文字列から最初の `{...}` JSONオブジェクトを抽出する
    /// - エージェントの出力にログや前置きが混入する場合に備えるためのヘルパー
    private func extractJSONObject(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end else {
            return nil
        }
        return String(raw[start...end])
    }

    /// 設定された要約エンジンでプロンプトを実行して stdout を返す
    private func runLLM(prompt: String, workingDirectory: URL) throws -> String {
        switch PostProcessingSettings.shared.summaryEngine {
        case .codex:
            return try runCodexSummary(prompt: prompt, workingDirectory: workingDirectory)
        case .claudeCode:
            return try runClaudeSummary(prompt: prompt, workingDirectory: workingDirectory)
        }
    }

    // -------------------------------------------------------------------------
    // 文字起こし処理
    // -------------------------------------------------------------------------

    /// whisperコマンドを使用して音声を文字起こし
    /// - Parameters:
    ///   - audioURL: 処理対象の音声ファイルURL
    ///   - outputFolder: 出力先フォルダ（省略時は音声ファイルと同じフォルダ）
    /// - Returns: 生成された文字起こしファイルのURL
    private func transcribe(audioURL: URL, outputFolder: URL? = nil) async throws -> URL {
        guard let whisperPath = findWhisperPath() else {
            print("PostProcessor: whisper command not found")
            throw PostProcessingError.whisperNotFound
        }

        let outputDir = (outputFolder ?? audioURL.deletingLastPathComponent()).path
        let baseName = audioURL.deletingPathExtension().lastPathComponent

        print("PostProcessor: whisper path \(whisperPath)")
        print("PostProcessor: whisper output dir \(outputDir)")

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
            // プロセスを登録（アプリ終了時にクリーンアップできるようにする）
            registerProcess(process)
            defer { unregisterProcess(process) }

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                print("PostProcessor: whisper failed: \(errorMessage)")
                throw PostProcessingError.transcriptionFailed(errorMessage)
            }

            // whisperは自動的に .txt ファイルを生成する
            let transcriptURL = (outputFolder ?? audioURL.deletingLastPathComponent())
                .appendingPathComponent("\(baseName).txt")

            // ファイルが生成されたか確認
            if !FileManager.default.fileExists(atPath: transcriptURL.path) {
                print("PostProcessor: transcript not found at \(transcriptURL.path)")
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

    /// 選択されたCLIエンジンを使用して文字起こしを要約
    /// - Parameters:
    ///   - transcriptURL: 文字起こしファイルのURL
    ///   - baseName: ベースファイル名（拡張子なし、省略時は文字起こしファイルから取得）
    ///   - outputFolder: 出力先フォルダ（省略時は文字起こしファイルと同じフォルダ）
    /// - Returns: 生成された要約ファイルのURL
    private func summarize(transcriptURL: URL, baseName: String? = nil, outputFolder: URL? = nil) async throws -> URL {
        // 出力ファイルのパスを生成
        let actualBaseName = baseName ?? transcriptURL.deletingPathExtension().lastPathComponent
        let summaryURL = (outputFolder ?? transcriptURL.deletingLastPathComponent())
            .appendingPathComponent("\(actualBaseName)_summary.md")

        // カレントディレクトリとして設定するフォルダ（文字起こしファイルのフォルダ）
        let workingDirectory = transcriptURL.deletingLastPathComponent()

        // 相対パスで文字起こしファイルを参照
        let transcriptFileName = transcriptURL.lastPathComponent

        let engine = PostProcessingSettings.shared.summaryEngine
        print("PostProcessor: summary engine \(engine.displayName)")
        print("PostProcessor: working directory \(workingDirectory.path)")
        print("PostProcessor: transcript file \(transcriptFileName)")
        print("PostProcessor: summary output \(summaryURL.path)")

        // 要約プロンプト（共通）
        let prompt = summaryPrompt(transcriptFileName: transcriptFileName)

        // エンジンごとに要約を実行し、Markdown本文を取得
        let summaryContent: String
        switch engine {
        case .codex:
            summaryContent = try runCodexSummary(prompt: prompt, workingDirectory: workingDirectory)
        case .claudeCode:
            summaryContent = try runClaudeSummary(prompt: prompt, workingDirectory: workingDirectory)
        }

        // 要約をファイルに保存
        try summaryContent.write(to: summaryURL, atomically: true, encoding: .utf8)

        return summaryURL
    }

    /// 要約プロンプトを生成
    private func summaryPrompt(transcriptFileName: String) -> String {
        return """
カレントディレクトリにある「\(transcriptFileName)」ファイルを読み込んでください。
このファイルには、会議の音声を自動文字起こししたデータが含まれています。
複数の話者による会話が混在している可能性があるため、内容を適切に解釈し、マークダウン形式で要約してください。

ファイル保存の指示は不要です。標準出力にMarkdown本文のみを出力してください。
前置きや説明文は書かず、本文だけを返してください。

## 出力形式
以下の形式で要約を作成してください：

# 概要
（会議全体の概要を1-2文で）

# 議事録
話し合われた内容をテーマごとにまとめ、各テーマ内で話題ごとに整理してください。
後で見返した時にどんな会話が行われたか思い出せるように、適切な粒度で過不足なく記載してください。

## （テーマ1のタイトル）

### （話題1のタイトル）
- （話題1の内容）

### （話題2のタイトル）
- （話題2の内容）

## （テーマ2のタイトル）

### （話題3のタイトル）
- （話題3の内容）

...

# 決定事項
- （決定事項1）
- （決定事項2）
...

（決定事項がない場合はこのセクション全体を省略してください）

# アクションアイテム
- [ ] （担当者）: （タスク内容）
- [ ] （担当者）: （タスク内容）
...

（アクションアイテムがない場合はこのセクション全体を省略してください）
"""
    }

    /// PATH を拡張した環境変数を返す（各CLIの検出用パスを先頭に追加）
    private func extendedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let path = environment["PATH"] {
            let extraPaths = [
                "/usr/local/bin",
                "/opt/homebrew/bin",
                "\(NSHomeDirectory())/.nodebrew/current/bin",
                "\(NSHomeDirectory())/.local/bin",
                "\(NSHomeDirectory())/bin",
                "\(NSHomeDirectory())/.npm-global/bin",
                "\(NSHomeDirectory())/.claude/local"
            ]
            environment["PATH"] = (extraPaths + [path]).joined(separator: ":")
        }
        return environment
    }

    /// codex exec で要約を実行（プロンプトは stdin 渡し）
    private func runCodexSummary(prompt: String, workingDirectory: URL) throws -> String {
        let codexPath = findCodexPath()
        let useEnv = codexPath == nil
        print("PostProcessor: codex path \(codexPath ?? "/usr/bin/env (PATH)")")

        let process = Process()
        if let codexPath = codexPath {
            process.executableURL = URL(fileURLWithPath: codexPath)
            process.arguments = ["exec", "--skip-git-repo-check"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["codex", "exec", "--skip-git-repo-check"]
        }
        process.currentDirectoryURL = workingDirectory
        process.environment = extendedEnvironment()

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            registerProcess(process)
            defer { unregisterProcess(process) }

            try process.run()
            if let inputData = prompt.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(inputData)
            }
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                print("PostProcessor: codex failed: \(errorMessage)")
                if useEnv && errorMessage.contains("codex") && errorMessage.contains("not found") {
                    throw PostProcessingError.codexNotFound
                }
                throw PostProcessingError.summaryFailed(errorMessage)
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let summaryContent = String(data: outputData, encoding: .utf8),
                  !summaryContent.isEmpty else {
                print("PostProcessor: codex output empty")
                throw PostProcessingError.summaryFailed("要約の出力が空です")
            }
            return summaryContent

        } catch let error as PostProcessingError {
            throw error
        } catch {
            throw PostProcessingError.summaryFailed(error.localizedDescription)
        }
    }

    /// claude (Claude Code) で要約を実行（プロンプトは引数、stdoutからtext取得）
    private func runClaudeSummary(prompt: String, workingDirectory: URL) throws -> String {
        let claudePath = findClaudePath()
        let useEnv = claudePath == nil
        print("PostProcessor: claude path \(claudePath ?? "/usr/bin/env (PATH)")")

        let process = Process()
        if let claudePath = claudePath {
            process.executableURL = URL(fileURLWithPath: claudePath)
            process.arguments = ["-p", prompt, "--output-format", "text"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["claude", "-p", prompt, "--output-format", "text"]
        }
        process.currentDirectoryURL = workingDirectory
        process.environment = extendedEnvironment()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            registerProcess(process)
            defer { unregisterProcess(process) }

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                print("PostProcessor: claude failed: \(errorMessage)")
                if useEnv && errorMessage.contains("claude") && errorMessage.contains("not found") {
                    throw PostProcessingError.claudeNotFound
                }
                throw PostProcessingError.summaryFailed(errorMessage)
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let summaryContent = String(data: outputData, encoding: .utf8),
                  !summaryContent.isEmpty else {
                print("PostProcessor: claude output empty")
                throw PostProcessingError.summaryFailed("要約の出力が空です")
            }
            return summaryContent

        } catch let error as PostProcessingError {
            throw error
        } catch {
            throw PostProcessingError.summaryFailed(error.localizedDescription)
        }
    }
}
