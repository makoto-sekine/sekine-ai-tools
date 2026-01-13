import Foundation

// =============================================================================
// PostProcessingSettings - 録音後処理の設定を管理するクラス
// =============================================================================
// このクラスは録音終了後の自動処理（文字起こし・要約）の
// 有効/無効設定を管理します。設定はUserDefaultsに保存され、
// アプリ再起動後も保持されます。
// =============================================================================

class PostProcessingSettings {

    // -------------------------------------------------------------------------
    // シングルトンインスタンス
    // -------------------------------------------------------------------------

    /// 共有インスタンス（アプリ全体で1つのインスタンスを使用）
    static let shared = PostProcessingSettings()

    // -------------------------------------------------------------------------
    // UserDefaultsキー
    // -------------------------------------------------------------------------

    /// 文字起こし有効/無効の設定キー
    private let transcriptionEnabledKey = "isTranscriptionEnabled"

    /// 要約有効/無効の設定キー
    private let summaryEnabledKey = "isSummaryEnabled"

    // -------------------------------------------------------------------------
    // プロパティ
    // -------------------------------------------------------------------------

    /// 文字起こしが有効かどうか
    /// - whisperコマンドを使用して音声をテキストに変換
    /// - デフォルトはfalse（無効）
    var isTranscriptionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: transcriptionEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: transcriptionEnabledKey) }
    }

    /// 要約が有効かどうか
    /// - codex execコマンドを使用してマークダウン形式の要約を生成
    /// - 文字起こしが無効の場合は常にfalseを返す
    /// - デフォルトはfalse（無効）
    var isSummaryEnabled: Bool {
        get {
            // 文字起こしが無効なら要約も無効
            guard isTranscriptionEnabled else { return false }
            return UserDefaults.standard.bool(forKey: summaryEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: summaryEnabledKey) }
    }

    // -------------------------------------------------------------------------
    // 初期化
    // -------------------------------------------------------------------------

    /// プライベート初期化（シングルトンパターン）
    private init() {}
}
