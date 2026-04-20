# TimeManager

macOS デスクトップ背景に常駐する縦型タイムラインマネージャー。30分スロット + 結合 + 色タグで「実績」を低摩擦に記録する個人用ツール。

## 仕様

- 要件: [docs/brainstorms/2026-04-17-desktop-timeline-manager-requirements.md](docs/brainstorms/2026-04-17-desktop-timeline-manager-requirements.md)
- 実装計画: [docs/plans/2026-04-17-001-feat-desktop-timeline-manager-plan.md](docs/plans/2026-04-17-001-feat-desktop-timeline-manager-plan.md)

## ビルド

プロジェクトは [XcodeGen](https://github.com/yonaskolb/XcodeGen) で管理しています。`project.yml` から `TimeManager.xcodeproj` を生成してビルドしてください。

```bash
brew install xcodegen          # 初回のみ
xcodegen generate              # project.yml → TimeManager.xcodeproj
open TimeManager.xcodeproj     # Xcode で開いて ▶︎ Run
```

CLI で直接ビルドする場合:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project TimeManager.xcodeproj -scheme TimeManager -configuration Debug build
```

テスト:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project TimeManager.xcodeproj -scheme TimeManager -destination 'platform=macOS' test
```

## データ保存先

`~/TimeManager/` 配下に JSON ファイルで永続化されます（App Sandbox 無効）。

```
~/TimeManager/
├── days/YYYY-MM-DD.json   # 1日1ファイル
├── tags.json              # 色タグ定義
├── settings.json          # 設定
├── trash/                 # ソフトデリート
└── backups/               # 将来のバックアップ置き場
```

メニューバーアイコン → 「データフォルダを Finder で開く」で一発アクセスできます。

## 主要機能

- 背景固定ウィンドウ (`NSWindow.Level.desktopIcon + 1`)
- 30分スロット / インライン編集 / 色タグ（開発・会議・休憩・調査・その他）
- 隣接スロット結合・分割・リサイズ（コンテキストメニュー）
- 過去日ナビゲーション（前日/翌日ボタン、`←`/`→`、日付ピッカー）
- 30分ごとのローカル通知（3回未応答で当日抑止）
- Markdown クリップボードコピー（メニューバーから）
- オンボーディング（通知許可・既定時間範囲・自動起動）

## 既知の未実装 (Phase 5 以降)

- Developer ID 署名 / Notarization / Sparkle 自動更新
- ゴミ箱 UI（30日自動パージロジック）と週次バックアップ ZIP
- 端ドラッグでのリサイズ・長押し分割（現在はコンテキストメニューで代替）
- macOS 12 でのログイン時自動起動（macOS 13+ は `SMAppService` で対応済）
