import SwiftUI
import AppKit

// =============================================================================
// QueueView - キュー管理画面
// =============================================================================
// 録音タスクの一覧を表示し、文字起こし・要約の状態を確認・実行できる画面
// =============================================================================

struct QueueView: View {
    @ObservedObject var queueManager = QueueManager.shared

    /// エクスポート確認中のアイテム
    @State private var itemPendingExport: QueueItem?

    /// エクスポート結果メッセージ（成功/失敗）
    @State private var exportResultMessage: String?

    /// エクスポート結果が失敗かどうか
    @State private var exportResultIsError: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            headerView

            Divider()

            // タスク一覧
            if queueManager.items.isEmpty {
                emptyStateView
            } else {
                taskListView
            }

            Divider()

            // フッター
            footerView
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            queueManager.refreshQueue()
        }
        // エクスポート確認ダイアログ
        .alert(
            "Obsidianへエクスポート",
            isPresented: Binding(
                get: { itemPendingExport != nil },
                set: { if !$0 { itemPendingExport = nil } }
            ),
            presenting: itemPendingExport
        ) { item in
            Button("キャンセル", role: .cancel) { itemPendingExport = nil }
            Button("実行", role: .destructive) {
                let target = item
                itemPendingExport = nil
                performExport(item: target)
            }
        } message: { item in
            Text("「\(item.displayTitle)」の要約を Obsidian に移動し、録音・文字起こしを削除します。よろしいですか？")
        }
        // エクスポート結果表示
        .alert(
            exportResultIsError ? "エクスポート失敗" : "エクスポート完了",
            isPresented: Binding(
                get: { exportResultMessage != nil },
                set: { if !$0 { exportResultMessage = nil } }
            )
        ) {
            Button("OK") { exportResultMessage = nil }
        } message: {
            Text(exportResultMessage ?? "")
        }
    }

    /// エクスポートを実行する
    private func performExport(item: QueueItem) {
        Task {
            do {
                let destURL = try await queueManager.exportToObsidian(item: item)
                await MainActor.run {
                    exportResultIsError = false
                    exportResultMessage = "エクスポートしました:\n\(destURL.path)"
                }
            } catch {
                await MainActor.run {
                    exportResultIsError = true
                    exportResultMessage = error.localizedDescription
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // ヘッダー
    // -------------------------------------------------------------------------

    private var headerView: some View {
        HStack {
            Text("キュー管理")
                .font(.headline)

            Spacer()

            Button(action: { queueManager.refreshQueue() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("更新")

            Button(action: { queueManager.openInFinder() }) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("フォルダを開く")
        }
        .padding()
    }

    // -------------------------------------------------------------------------
    // 空状態の表示
    // -------------------------------------------------------------------------

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("タスクがありません")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("録音を開始すると、ここにタスクが表示されます")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // -------------------------------------------------------------------------
    // タスク一覧
    // -------------------------------------------------------------------------

    private var taskListView: some View {
        List(queueManager.items) { item in
            queueItemRowView(for: item)
        }
        .listStyle(.inset)
    }

    private func queueItemRowView(for item: QueueItem) -> some View {
        let isProcessing = queueManager.processingItemId.map { $0 == item.id } ?? false
        let isExporting = queueManager.exportingItemId.map { $0 == item.id } ?? false
        let isPending = queueManager.pendingTasks.contains(where: { $0.itemId == item.id })
        return QueueItemRow(
            item: item,
            isProcessing: isProcessing,
            isExporting: isExporting,
            isPending: isPending,
            onTranscribe: { queueManager.transcribe(item: item) },
            onSummarize: { queueManager.summarize(item: item) },
            onProcessAll: { queueManager.processAll(item: item) },
            onDelete: { queueManager.deleteItem(item) },
            onExport: { itemPendingExport = item },
            onOpenAudio: { NSWorkspace.shared.open(item.audioURL) },
            onOpenTranscript: {
                if let url = item.transcriptURL {
                    NSWorkspace.shared.open(url)
                }
            },
            onOpenSummary: {
                if let url = item.summaryURL {
                    NSWorkspace.shared.open(url)
                }
            },
            onOpenFolder: { queueManager.openItemFolderInFinder(item) },
            onRename: { newId in
                _ = queueManager.renameItem(item, to: newId)
            }
        )
    }

    // -------------------------------------------------------------------------
    // フッター
    // -------------------------------------------------------------------------

    private var footerView: some View {
        HStack {
            // ステータス別の件数表示
            let recordedCount = queueManager.items.filter { $0.status == .recorded }.count
            let transcribedCount = queueManager.items.filter { $0.status == .transcribed }.count
            let summarizedCount = queueManager.items.filter { $0.status == .summarized }.count

            HStack(spacing: 16) {
                statusBadge(count: recordedCount, status: .recorded)
                statusBadge(count: transcribedCount, status: .transcribed)
                statusBadge(count: summarizedCount, status: .summarized)
            }

            Spacer()

            // 全て処理ボタン
            let pendingCount = queueManager.items.filter { $0.needsTranscription || $0.needsSummary }.count
            if pendingCount > 0 {
                Button("全て処理 (\(pendingCount)件)") {
                    queueManager.processAllPending()
                }
            }
        }
        .padding()
    }

    private func statusBadge(count: Int, status: TaskStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .help(status.rawValue)
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .recorded: return .orange
        case .transcribed: return .blue
        case .summarized: return .green
        }
    }
}

// =============================================================================
// QueueItemRow - タスク行のビュー
// =============================================================================

struct QueueItemRow: View {
    let item: QueueItem
    let isProcessing: Bool
    let isExporting: Bool
    let isPending: Bool
    let onTranscribe: () -> Void
    let onSummarize: () -> Void
    let onProcessAll: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void
    let onOpenAudio: () -> Void
    let onOpenTranscript: () -> Void
    let onOpenSummary: () -> Void
    let onOpenFolder: () -> Void
    let onRename: (String) -> Void

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var newId: String = ""

    var body: some View {
        HStack(spacing: 12) {
            // ステータスインジケーター
            statusIndicator

            // メイン情報
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.formattedFileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(item.status.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.2))
                        .foregroundColor(statusColor)
                        .cornerRadius(4)
                }
            }

            Spacer()

            // アクションボタン
            if isProcessing {
                ProgressView()
                    .controlSize(.small)
                Text("処理中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if isExporting {
                ProgressView()
                    .controlSize(.small)
                Text("エクスポート中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if isPending {
                Text("待機中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if isHovering {
                actionButtons
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            contextMenuItems
        }
        .sheet(isPresented: $isRenaming) {
            RenameSheet(
                currentId: item.id,
                newId: $newId,
                onSave: {
                    onRename(newId)
                    isRenaming = false
                },
                onCancel: {
                    isRenaming = false
                }
            )
        }
    }

    /// リネームシートを表示
    func showRenameSheet() {
        newId = item.id
        isRenaming = true
    }

    // ステータスインジケーター
    private var statusIndicator: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(item.transcriptURL != nil ? Color.blue : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 2, height: 8)
            Circle()
                .fill(item.summaryURL != nil ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
        }
    }

    // ステータスに応じた色
    private var statusColor: Color {
        switch item.status {
        case .recorded: return .orange
        case .transcribed: return .blue
        case .summarized: return .green
        }
    }

    // アクションボタン
    private var actionButtons: some View {
        HStack(spacing: 8) {
            // 音声を開く
            Button(action: onOpenAudio) {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("音声を再生")

            // 文字起こしを開く（存在する場合）
            if item.transcriptURL != nil {
                Button(action: onOpenTranscript) {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.borderless)
                .help("文字起こしを開く")
            }

            // 要約を開く（存在する場合）
            if item.summaryURL != nil {
                Button(action: onOpenSummary) {
                    Image(systemName: "doc.richtext")
                }
                .buttonStyle(.borderless)
                .help("要約を開く")
            }

            Divider()
                .frame(height: 16)

            // 処理ボタン
            if item.needsTranscription {
                Button(action: onTranscribe) {
                    Image(systemName: "text.bubble")
                }
                .buttonStyle(.borderless)
                .help("文字起こしを実行")
            }

            if item.needsSummary {
                Button(action: onSummarize) {
                    Image(systemName: "doc.badge.gearshape")
                }
                .buttonStyle(.borderless)
                .help("要約を実行")
            }

            if item.needsTranscription || item.needsSummary {
                Button(action: onProcessAll) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help("全て処理")
            }

            // Obsidianへエクスポート（要約済みのみ）
            if item.status == .summarized {
                Button(action: onExport) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("Obsidianへエクスポート")
            }
        }
    }

    // コンテキストメニュー
    private var contextMenuItems: some View {
        Group {
            Button("音声を再生", action: onOpenAudio)

            if item.transcriptURL != nil {
                Button("文字起こしを開く", action: onOpenTranscript)
            }

            if item.summaryURL != nil {
                Button("要約を開く", action: onOpenSummary)
            }

            Button("フォルダを開く", action: onOpenFolder)

            Divider()

            if item.needsTranscription {
                Button("文字起こしを実行", action: onTranscribe)
            }

            if item.needsSummary {
                Button("要約を実行", action: onSummarize)
            }

            if item.needsTranscription || item.needsSummary {
                Button("全て処理", action: onProcessAll)
            }

            if item.status == .summarized {
                Divider()
                Button("Obsidianへエクスポート", action: onExport)
            }

            Divider()

            Button("名前を変更...") {
                newId = item.id
                isRenaming = true
            }

            Button("削除", role: .destructive, action: onDelete)
        }
    }
}

// =============================================================================
// RenameSheet - 名前変更ダイアログ
// =============================================================================

struct RenameSheet: View {
    let currentId: String
    @Binding var newId: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("名前を変更")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("新しい名前:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("ID", text: $newId)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
            }

            HStack {
                Button("キャンセル", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("変更") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newId.isEmpty || newId == currentId)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

// =============================================================================
// QueueWindowController - キュー画面のウィンドウコントローラー
// =============================================================================

class QueueWindowController: NSWindowController {
    static let shared = QueueWindowController()

    private init() {
        let hostingController = NSHostingController(rootView: QueueView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "キュー管理"
        window.setContentSize(NSSize(width: 600, height: 500))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
