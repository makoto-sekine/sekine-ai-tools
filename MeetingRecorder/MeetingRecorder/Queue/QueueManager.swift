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

        // キューを読み込み
        refreshQueue()
    }

    // -------------------------------------------------------------------------
    // キューの更新
    // -------------------------------------------------------------------------

    /// キューをファイルシステムから再読み込み
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

        DispatchQueue.main.async {
            self.items = newItems
        }
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
            refreshQueue()

            // アイテムを検索
            guard let item = items.first(where: { $0.id == nextTask.itemId }) else {
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
                    refreshQueue()
                }

            case .summarizeOnly:
                // 要約のみ
                if item.needsSummary && PostProcessingSettings.shared.isSummaryEnabled {
                    print("QueueManager: Processing summary for \(item.id)")
                    _ = await summarizeInternal(item: item)
                    refreshQueue()
                }

            case .processAll:
                // 文字起こし→要約
                if item.needsTranscription && PostProcessingSettings.shared.isTranscriptionEnabled {
                    print("QueueManager: Processing transcription for \(item.id)")
                    _ = await transcribeInternal(item: item)
                    refreshQueue()
                }

                // 最新の状態を取得
                guard let updatedItem = items.first(where: { $0.id == nextTask.itemId }) else {
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
                    refreshQueue()
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

    /// 指定アイテムのフォルダをFinderで開く
    func openItemFolderInFinder(_ item: QueueItem) {
        NSWorkspace.shared.open(item.folderURL)
    }
}
