import SwiftUI
import AppKit

// =============================================================================
// MeetingRecorderApp - アプリケーションのエントリーポイント
// =============================================================================
// このファイルはアプリケーションの起動点（エントリーポイント）です。
// @mainマクロによって、プログラムはここから実行を開始します。
// =============================================================================

/// @main: このstructがアプリケーションの開始点であることを示す
@main
struct MeetingRecorderApp: App {

    // AppDelegateを使用することをSwiftUIに伝える
    // NSApplicationDelegateAdaptorを使うと、SwiftUIアプリでも
    // 従来のAppDelegateパターンを使用できる
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// アプリケーションの画面構成を定義するプロパティ
    /// このアプリはメニューバー常駐型なので、メインウィンドウは不要
    var body: some Scene {
        // Settings: 設定画面用のシーン（今回は空のビューを表示）
        // メニューバーアプリなのでウィンドウは表示しない
        Settings {
            EmptyView()
        }
    }
}
