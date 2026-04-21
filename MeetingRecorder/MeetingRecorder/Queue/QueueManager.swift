import Foundation
import Combine
import AppKit

// =============================================================================
// QueueManager - キュー管理クラス
// =============================================================================
// 録音タスクのキューを管理し、ファイルの有無でステータスを判定します。
//
// フォルダ構成:
// ~/Documents/MeetingRecordings/
//   ├── audio/       - 音声ファイル (.mp3, .m4a, .wav)
//   ├── transcripts/ - 文字起こし (.txt)
//   └── summaries/   - 要約 (.md)
// =============================================================================

class QueueManager: ObservableObject {

    // -------------------------------------------------------------------------
    // シングルトン
    // -------------------------------------------------------------------------

    /// 共有インスタンス
    static let shared = QueueManager()

    // -------------------------------------------------------------------------
    // Published プロパティ
    // -------------------------------------------------------------------------

    /// キューに入っているタスク一覧
    @Published var items: [QueueItem] = []

    /// 現在処理中のアイテムID
    @Published var processingItemId: String?

    /// 現在エクスポート中のアイテムID
    @Published var exportingItemId: String?

    /// 処理タスクの種類
    enum TaskType: CustomStringConvertible {
        case transcribeOnly
        case summarizeOnly
        case processAll

        var description: String {
            switch self {
            case .transcribeOnly: return "文字起こし"
            case .summarizeOnly: return "要約"
            case .processAll: return "全処理"
            }
        }
    }

    /// 処理タスク
    struct ProcessingTask {
        let itemId: String
        let taskType: TaskType
    }

    /// エクスポート処理で発生するエラー
    enum ExportError: LocalizedError {
        case vaultNotSet
        case summaryMissing
        case fileOperationFailed(String)

        var errorDescription: String? {
            switch self {
            case .vaultNotSet:
                return "Obsidian Vault が未設定です。メニューから Vault を選択してください。"
            case .summaryMissing:
                return "要約ファイルがありません。エクスポートできるのは要約済みのアイテムのみです。"
            case .fileOperationFailed(let message):
                return "ファイル操作に失敗しました: \(message)"
            }
        }
    }

    // -------------------------------------------------------------------------
    // フォルダパス
    // -------------------------------------------------------------------------

    /// ベースフォルダ
    let baseFolder: URL

    /// 指定されたIDのフォルダを取得
    func itemFolder(for id: String) -> URL {
        return baseFolder.appendingPathComponent(id)
    }

    /// 指定されたIDのフォルダを作成
    func createItemFolder(for id: String) -> URL {
        let folder = itemFolder(for: id)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // -------------------------------------------------------------------------
    // 後処理
    // -------------------------------------------------------------------------

    /// 後処理を実行するクラス
    private let postProcessor = PostProcessor()

    /// 処理キュー（直列実行用）
    private let processingQueue = DispatchQueue(label: "com.meetingrecorder.processing", qos: .userInitiated)

    /// 現在処理中かどうか
    private var isProcessingQueue = false

    /// 処理待ちのタスク
    @Published var pendingTasks: [ProcessingTask] = []

    // -------------------------------------------------------------------------
    // 初期化
    // -------------------------------------------------------------------------

    private init() {
        // ドキュメントフォルダのパスを取得
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseFolder = documentsPath.appendingPathComponent("MeetingRecordings")

        // ベースフォルダを作成
        try? FileManager.default.createDirectory(at: baseFolder, withIntermediateDirectories: true)

        // キューを読み込み（非同期で実行）
        Task { @MainActor in
            self.refreshQueue()
        }
    }

    // -------------------------------------------------------------------------
    // キューの更新
    // -------------------------------------------------------------------------

    /// キューをファイルシステムから再読み込み
    @MainActor
    func refreshQueue() {
        let fileManager = FileManager.default

        // ベースフォルダ内のサブフォルダを取得
        guard let subfolders = try? fileManager.contentsOfDirectory(
            at: baseFolder,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            items = []
            return
        }

        // 音声ファイルの拡張子
        let audioExtensions = ["mp3", "m4a", "wav"]

        // QueueItemを作成
        var newItems: [QueueItem] = []

        for subfolder in subfolders {
            // ディレクトリかどうか確認
            guard let resourceValues = try? subfolder.resourceValues(forKeys: [.isDirectoryKey]),
                  resourceValues.isDirectory == true else {
                continue
            }

            let id = subfolder.lastPathComponent

            // フォルダ内のファイルを取得
            guard let files = try? fileManager.contentsOfDirectory(
                at: subfolder,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            // 音声ファイルを検索
            var audioURL: URL?
            var transcriptURL: URL?
            var summaryURL: URL?
            var recordedAt: Date?

            for file in files {
                let ext = file.pathExtension.lowercased()
                let fileName = file.deletingPathExtension().lastPathComponent

                if audioExtensions.contains(ext) {
                    audioURL = file
                    // 録音日時を取得
                    if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                       let creationDate = attributes[.creationDate] as? Date {
                        recordedAt = creationDate
                    }
                } else if ext == "txt" {
                    transcriptURL = file
                } else if ext == "md" && fileName.hasSuffix("_summary") {
                    summaryURL = file
                }
            }

            // 音声ファイルがなければスキップ
            guard let audio = audioURL else { continue }

            let item = QueueItem(
                id: id,
                folderURL: subfolder,
                recordedAt: recordedAt,
                audioURL: audio,
                transcriptURL: transcriptURL,
                summaryURL: summaryURL
            )

            newItems.append(item)
        }

        // 日時の新しい順にソート
        newItems.sort { ($0.recordedAt ?? .distantPast) > ($1.recordedAt ?? .distantPast) }

        // 同期的に更新（@MainActorで保証されている）
        self.items = newItems
    }

    // -------------------------------------------------------------------------
    // キューへの追加（外部から呼び出す用）
    // -------------------------------------------------------------------------

    /// 音声ファイルを処理キューに追加（録音完了時に呼び出される）
    /// - Parameter audioURL: 処理対象の音声ファイルURL
    func enqueueForProcessing(audioURL: URL) {
        let baseName = audioURL.deletingPathExtension().lastPathComponent

        DispatchQueue.main.async {
            // 既にキューに入っている場合はスキップ
            guard !self.pendingTasks.contains(where: { $0.itemId == baseName }) else { return }

            let task = ProcessingTask(itemId: baseName, taskType: .processAll)
            self.pendingTasks.append(task)
            print("QueueManager: Enqueued \(baseName) for processing")

            // キューの処理を開始
            self.processNextInQueue()
        }
    }

    /// タスクをキューに追加（手動実行用）
    private func enqueueTask(itemId: String, taskType: TaskType) {
        DispatchQueue.main.async {
            // 既に同じタスクがキューに入っている場合はスキップ
            guard !self.pendingTasks.contains(where: { $0.itemId == itemId && $0.taskType == taskType }) else {
                print("QueueManager: Task already in queue: \(itemId) - \(taskType)")
                return
            }

            let task = ProcessingTask(itemId: itemId, taskType: taskType)
            self.pendingTasks.append(task)
            print("QueueManager: Enqueued task: \(itemId) - \(taskType)")

            // キューの処理を開始
            self.processNextInQueue()
        }
    }

    /// キュー内の次のアイテムを処理
    private func processNextInQueue() {
        // 既に処理中の場合は何もしない
        guard !isProcessingQueue else {
            print("QueueManager: Already processing, skipping")
            return
        }

        // キューが空の場合は何もしない
        guard let nextTask = pendingTasks.first else {
            print("QueueManager: Queue is empty")
            return
        }

        isProcessingQueue = true
        print("QueueManager: Starting task: \(nextTask.itemId) - \(nextTask.taskType)")

        Task {
            // 最新のキューを取得
            await refreshQueue()

            // アイテムを検索
            let item = await MainActor.run {
                items.first(where: { $0.id == nextTask.itemId })
            }

            guard let item = item else {
                // アイテムが見つからない場合はスキップ
                print("QueueManager: Item not found: \(nextTask.itemId)")
                await MainActor.run {
                    self.pendingTasks.removeFirst()
                    self.isProcessingQueue = false
                    self.processNextInQueue()
                }
                return
            }

            // タスクの種類に応じて処理を実行
            switch nextTask.taskType {
            case .transcribeOnly:
                // 文字起こしのみ
                if item.needsTranscription && PostProcessingSettings.shared.isTranscriptionEnabled {
                    print("QueueManager: Processing transcription for \(item.id)")
                    _ = await transcribeInternal(item: item)
                    await refreshQueue()
                }

            case .summarizeOnly:
                // 要約のみ
                if item.needsSummary && PostProcessingSettings.shared.isSummaryEnabled {
                    print("QueueManager: Processing summary for \(item.id)")
                    _ = await summarizeInternal(item: item)
                    await refreshQueue()
                }

            case .processAll:
                // 文字起こし→要約
                if item.needsTranscription && PostProcessingSettings.shared.isTranscriptionEnabled {
                    print("QueueManager: Processing transcription for \(item.id)")
                    _ = await transcribeInternal(item: item)
                    await refreshQueue()
                }

                // 最新の状態を取得
                let updatedItem = await MainActor.run {
                    items.first(where: { $0.id == nextTask.itemId })
                }

                guard let updatedItem = updatedItem else {
                    await MainActor.run {
                        self.pendingTasks.removeFirst()
                        self.isProcessingQueue = false
                        self.processNextInQueue()
                    }
                    return
                }

                // 要約を実行
                if updatedItem.needsSummary && PostProcessingSettings.shared.isSummaryEnabled {
                    print("QueueManager: Processing summary for \(updatedItem.id)")
                    _ = await summarizeInternal(item: updatedItem)
                    await refreshQueue()
                }
            }

            // 処理完了、次のアイテムへ
            await MainActor.run {
                self.pendingTasks.removeFirst()
                self.isProcessingQueue = false
                print("QueueManager: Completed task: \(nextTask.itemId) - \(nextTask.taskType)")
                self.processNextInQueue()
            }
        }
    }

    // -------------------------------------------------------------------------
    // 処理の実行（内部用）
    // -------------------------------------------------------------------------

    /// 指定されたアイテムの文字起こしを実行（内部用）
    private func transcribeInternal(item: QueueItem) async -> URL? {
        guard item.needsTranscription else { return item.transcriptURL }

        DispatchQueue.main.async {
            self.processingItemId = item.id
        }

        defer {
            DispatchQueue.main.async {
                self.processingItemId = nil
            }
        }

        do {
            let transcriptURL = try await postProcessor.transcribeOnly(
                audioURL: item.audioURL,
                outputFolder: item.folderURL
            )
            return transcriptURL
        } catch {
            print("Transcription failed for \(item.id): \(error)")
            return nil
        }
    }

    /// 指定されたアイテムの要約を実行（内部用）
    private func summarizeInternal(item: QueueItem) async -> URL? {
        guard let transcriptURL = item.transcriptURL else { return nil }
        guard item.needsSummary else { return item.summaryURL }

        DispatchQueue.main.async {
            self.processingItemId = item.id
        }

        defer {
            DispatchQueue.main.async {
                self.processingItemId = nil
            }
        }

        do {
            let summaryURL = try await postProcessor.summarizeOnly(
                transcriptURL: transcriptURL,
                baseName: item.id,
                outputFolder: item.folderURL
            )
            return summaryURL
        } catch {
            print("Summary failed for \(item.id): \(error)")
            return nil
        }
    }

    // -------------------------------------------------------------------------
    // 処理の実行（UI から手動実行用）
    // -------------------------------------------------------------------------

    /// 指定されたアイテムの文字起こしを実行（手動実行用）
    func transcribe(item: QueueItem) {
        enqueueTask(itemId: item.id, taskType: .transcribeOnly)
    }

    /// 指定されたアイテムの要約を実行（手動実行用）
    func summarize(item: QueueItem) {
        enqueueTask(itemId: item.id, taskType: .summarizeOnly)
    }

    /// 指定されたアイテムの全処理を実行（文字起こし→要約）
    func processAll(item: QueueItem) {
        enqueueTask(itemId: item.id, taskType: .processAll)
    }

    /// 未処理のアイテムをすべて処理
    func processAllPending() {
        for item in items {
            if item.needsTranscription || item.needsSummary {
                enqueueTask(itemId: item.id, taskType: .processAll)
            }
        }
    }

    // -------------------------------------------------------------------------
    // ファイル操作
    // -------------------------------------------------------------------------

    /// アイテムを削除（フォルダごと削除）
    @MainActor
    func deleteItem(_ item: QueueItem) {
        let fileManager = FileManager.default

        // フォルダごと削除
        try? fileManager.removeItem(at: item.folderURL)

        refreshQueue()
    }

    /// アイテムのIDを変更（フォルダ名と全ファイル名を一括変更）
    /// - Parameters:
    ///   - item: 変更対象のアイテム
    ///   - newId: 新しいID
    /// - Returns: 成功したかどうか
    @MainActor
    @discardableResult
    func renameItem(_ item: QueueItem, to newId: String) -> Bool {
        let fileManager = FileManager.default

        // 新しいIDが空でないことを確認
        guard !newId.isEmpty else { return false }

        // 新しいIDが現在と同じ場合は何もしない
        guard newId != item.id else { return true }

        // 新しいフォルダパス
        let newFolderURL = baseFolder.appendingPathComponent(newId)

        // 新しいフォルダが既に存在する場合は失敗
        guard !fileManager.fileExists(atPath: newFolderURL.path) else {
            print("Rename failed: folder already exists at \(newFolderURL.path)")
            return false
        }

        do {
            // フォルダをリネーム
            try fileManager.moveItem(at: item.folderURL, to: newFolderURL)

            // フォルダ内のファイルをリネーム
            let files = try fileManager.contentsOfDirectory(at: newFolderURL, includingPropertiesForKeys: nil)

            for file in files {
                let oldFileName = file.lastPathComponent
                let ext = file.pathExtension

                // 新しいファイル名を生成
                let newFileName: String
                if oldFileName.hasSuffix("_summary.md") {
                    newFileName = "\(newId)_summary.md"
                } else {
                    newFileName = "\(newId).\(ext)"
                }

                let newFileURL = newFolderURL.appendingPathComponent(newFileName)

                // ファイル名が変わる場合のみリネーム
                if oldFileName != newFileName {
                    try fileManager.moveItem(at: file, to: newFileURL)
                }
            }

            refreshQueue()
            return true

        } catch {
            print("Rename failed: \(error)")
            return false
        }
    }

    /// Finderでフォルダを開く
    func openInFinder() {
        NSWorkspace.shared.open(baseFolder)
    }

    // -------------------------------------------------------------------------
    // Obsidianエクスポート
    // -------------------------------------------------------------------------

    /// Obsidian vault 配下の Meetings フォルダURL（vault が未設定なら nil）
    private func meetingsFolderURL() -> URL? {
        guard let vaultPath = PostProcessingSettings.shared.obsidianVaultPath,
              !vaultPath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: vaultPath).appendingPathComponent("Meetings")
    }

    /// 既存プロジェクトフォルダ一覧（Meetings配下の直下サブディレクトリ）
    private func existingProjects(in meetingsFolder: URL) -> [String] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: meetingsFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return (values?.isDirectory == true) ? url.lastPathComponent : nil
        }.sorted()
    }

    /// ファイル名として安全な文字列に整形する
    /// - ファイルシステムで問題になる記号を `_` に置換し、前後の空白・ドットを除去する
    private func sanitizeFileName(_ input: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let replaced = String(input.unicodeScalars.map { scalar -> Character in
            forbidden.contains(scalar) ? "_" : Character(scalar)
        })
        return replaced
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    /// Obsidianへエクスポートする
    /// - Parameter item: 対象アイテム（要約済みである必要あり）
    /// - Returns: 移動後の要約ファイルURL
    /// - Throws: `ExportError` または `PostProcessor.PostProcessingError`
    func exportToObsidian(item: QueueItem) async throws -> URL {
        // 事前チェック
        guard let meetingsFolder = meetingsFolderURL() else {
            throw ExportError.vaultNotSet
        }
        guard let summaryURL = item.summaryURL else {
            throw ExportError.summaryMissing
        }

        await MainActor.run { self.exportingItemId = item.id }
        defer {
            Task { @MainActor in self.exportingItemId = nil }
        }

        let fileManager = FileManager.default

        // Meetings フォルダを作成（なければ）
        try fileManager.createDirectory(at: meetingsFolder, withIntermediateDirectories: true)

        // 要約ファイルを読み込み
        let summaryContent: String
        do {
            summaryContent = try String(contentsOf: summaryURL, encoding: .utf8)
        } catch {
            throw ExportError.fileOperationFailed("要約ファイルの読み込みに失敗: \(error.localizedDescription)")
        }

        // 既存プロジェクトを列挙
        let existing = existingProjects(in: meetingsFolder)

        // エージェントでエクスポート先を判定
        let recordedDate = item.recordedAt ?? Date()
        let destination = try await postProcessor.decideExportDestination(
            summaryContent: summaryContent,
            existingProjects: existing,
            recordedDate: recordedDate,
            workingDirectory: item.folderURL
        )

        let projectName = sanitizeFileName(destination.project)
        let titlePart = sanitizeFileName(destination.title)
        guard !projectName.isEmpty, !titlePart.isEmpty else {
            throw ExportError.fileOperationFailed("エージェントが返したプロジェクト名または会議名が空です")
        }

        // プロジェクトフォルダを作成
        let projectFolder = meetingsFolder.appendingPathComponent(projectName)
        try fileManager.createDirectory(at: projectFolder, withIntermediateDirectories: true)

        // ファイル名を生成（YYYY-MM-DD_{title}.md、衝突時は連番）
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: recordedDate)
        let baseName = "\(dateString)_\(titlePart)"
        var destURL = projectFolder.appendingPathComponent("\(baseName).md")
        var suffix = 2
        while fileManager.fileExists(atPath: destURL.path) {
            destURL = projectFolder.appendingPathComponent("\(baseName)_\(suffix).md")
            suffix += 1
        }

        // 要約ファイルを移動
        do {
            try fileManager.moveItem(at: summaryURL, to: destURL)
        } catch {
            throw ExportError.fileOperationFailed("要約ファイルの移動に失敗: \(error.localizedDescription)")
        }

        // 元の録音フォルダを削除（音声・文字起こしも含めて一括削除）
        do {
            try fileManager.removeItem(at: item.folderURL)
        } catch {
            // 移動は成功したが元フォルダ削除失敗。警告のみ。
            print("QueueManager: failed to remove source folder: \(error)")
        }

        await refreshQueue()

        return destURL
    }

    /// 指定アイテムのフォルダをFinderで開く
    func openItemFolderInFinder(_ item: QueueItem) {
        NSWorkspace.shared.open(item.folderURL)
    }

    // -------------------------------------------------------------------------
    // クリーンアップ（アプリ終了時）
    // -------------------------------------------------------------------------

    /// アプリ終了時にすべての処理を停止する
    func cleanup() {
        // 実行中のプロセスをすべて終了
        postProcessor.cancelAllProcesses()

        // キュー処理をクリア
        DispatchQueue.main.async {
            self.pendingTasks.removeAll()
            self.isProcessingQueue = false
        }

        print("QueueManager: Cleanup completed")
    }
}
