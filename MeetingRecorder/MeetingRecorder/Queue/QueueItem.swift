import Foundation

// =============================================================================
// QueueItem - 録音タスクの状態を表す構造体
// =============================================================================
// 各録音フォルダに対して、文字起こし・要約の処理状態を管理します。
// ステータスは対応するファイルの有無で判断します。
//
// フォルダ構成:
// ~/Documents/MeetingRecordings/
//   └── {id}/
//       ├── {id}.m4a (音声)
//       ├── {id}.txt (文字起こし)
//       └── {id}_summary.md (要約)
// =============================================================================

/// 録音タスクのステータス
enum TaskStatus: String, CaseIterable {
    /// 録音済み（音声ファイルのみ存在）
    case recorded = "録音済み"
    /// 文字起こし済み（txtファイルも存在）
    case transcribed = "文字起こし済み"
    /// 要約済み（mdファイルも存在）
    case summarized = "要約済み"

    /// ステータスに応じた色
    var colorName: String {
        switch self {
        case .recorded:
            return "orange"
        case .transcribed:
            return "blue"
        case .summarized:
            return "green"
        }
    }
}

/// 録音タスクを表す構造体
struct QueueItem: Identifiable, Equatable {
    /// 一意識別子（フォルダ名 = ファイル名のベース）
    let id: String

    /// フォルダのURL
    let folderURL: URL

    /// 表示用のタイトル
    var displayTitle: String {
        // 日付部分を読みやすく変換（例: 2024-01-15_143022 → 2024/01/15 14:30）
        // パターン: タイトル_YYYY-MM-DD_HHMMSS
        let pattern = "^(.+?)_(\\d{4})-(\\d{2})-(\\d{2})_(\\d{2})(\\d{2})(\\d{2})$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) else {
            return id
        }

        func extractGroup(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: id) else { return nil }
            return String(id[range])
        }

        guard let title = extractGroup(1),
              let year = extractGroup(2),
              let month = extractGroup(3),
              let day = extractGroup(4),
              let hour = extractGroup(5),
              let minute = extractGroup(6) else {
            return id
        }

        if title == "recording" {
            return "\(year)/\(month)/\(day) \(hour):\(minute)"
        } else {
            return "\(title) (\(month)/\(day) \(hour):\(minute))"
        }
    }

    /// 録音日時
    let recordedAt: Date?

    /// 音声ファイルのURL
    let audioURL: URL

    /// 文字起こしファイルのURL（存在する場合）
    let transcriptURL: URL?

    /// 要約ファイルのURL（存在する場合）
    let summaryURL: URL?

    /// 現在のステータス（ファイルの有無から判定）
    var status: TaskStatus {
        if summaryURL != nil {
            return .summarized
        } else if transcriptURL != nil {
            return .transcribed
        } else {
            return .recorded
        }
    }

    /// 文字起こしが必要かどうか
    var needsTranscription: Bool {
        return transcriptURL == nil
    }

    /// 要約が必要かどうか
    var needsSummary: Bool {
        return transcriptURL != nil && summaryURL == nil
    }

    /// ファイルサイズ（フォーマット済み）
    var formattedFileSize: String {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: audioURL.path),
              let size = attributes[.size] as? Int64 else {
            return "不明"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // Equatableの実装
    static func == (lhs: QueueItem, rhs: QueueItem) -> Bool {
        return lhs.id == rhs.id
    }
}
