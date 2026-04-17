---
title: デスクトップ常駐型タイムラインマネージャー
type: feat
status: in-progress
date: 2026-04-17
origin: docs/brainstorms/2026-04-17-desktop-timeline-manager-requirements.md
---

# デスクトップ常駐型タイムラインマネージャー

## Overview

macOSデスクトップ背景に固定された縦型タイムラインウィンドウに、実績ベースで「何をしていたか」を低摩擦に記録できる個人用ツールをネイティブSwift/SwiftUIで新規構築する。30分スロット + 隣接スロット結合、テキスト + 色タグ、30分ごとのmacOS通知、過去日閲覧、日報流用のテキスト書き出しを含む。データは端末ローカル（ユーザーホーム直下 `~/TimeManager/` に1日1ファイルのJSONで保存、ユーザーが直接参照・バックアップ可能）し、Mac App Store外の個人配布を想定する。

## Problem Statement / Motivation

個人の業務において「実際に何に時間を使ったか」を振り返れる仕組みが欲しいが、従来のタイムトラッキングツールは以下のどれかに倒れがちで定着しない:

- 入力コストが高い（ツール切り替え・項目分類・開始終了操作）
- 自動トラッキング型で意図が混ざる（ブラウザ閲覧 = 作業とは限らない）
- 常に視界に無いため入力自体を忘れる

本ツールは「デスクトップ背景に常駐して目に入る」+「30分単位で最小の手間」という制約を最初に置くことで、継続的な実績記録と日報流用を同時に成立させる。

詳細は origin: `docs/brainstorms/2026-04-17-desktop-timeline-manager-requirements.md` 参照。

## Proposed Solution

**技術スタック: Swift/SwiftUI ネイティブ macOSアプリ** (詳細な選定理由はTechnical Considerationsを参照)

**主要構成:**

1. **NSWindow の `desktopIcon` 層固定** による「背景ウィジェット」体験
2. **SwiftUI の縦長タイムラインビュー** — 30分スロットグリッド + 現在時刻の赤ライン + 色タグ + インライン編集
3. **`~/TimeManager/` 配下のJSONファイル永続化** — 1日1ファイル + タグ定義 + 設定 + ゴミ箱を分離（ユーザーがFinderで中身を確認・バックアップ可能）
4. **UserNotifications による30分通知** — ローカル通知でアプリ未起動でも発火
5. **メニューバーアイコン** — 背景固定ウィンドウへの導線（強制再表示、設定、ON/OFFトグル）
6. **Developer ID署名 + Notarization + Sparkle** で個人配布（サンドボックス無効）

## Technical Considerations

### 技術スタック選定（Swift/SwiftUI ネイティブ）

| 比較軸 | Swift/SwiftUI | Electron | Tauri 2.x |
|---|---|---|---|
| 背景固定ウィンドウ | `NSWindow.Level` で標準対応 | macOSでは `type: 'desktop'` が機能せずネイティブブリッジ必須 | 公式APIに無く `objc2` カスタムプラグイン必要 |
| Stage Manager/Spaces制御 | `collectionBehavior` で細かく制御可 | 制御不可・不安定 | Rustから手動制御 |
| 配布サイズ | 数MB | 100MB超 | 10MB前後 |
| 開発工数 | 中（Swift習熟が前提） | ネイティブブリッジ必須で相殺 | ネイティブブリッジ必須で相殺 |

→ **要件の核心（背景固定）が標準APIで素直に書ける唯一のスタックがSwift/SwiftUI**。ElectronもTauriも結局ネイティブAPIを叩く羽目になり、その時点でSwiftで書くほうが総工数が小さい。

### 背景固定ウィンドウの実装ポイント

```swift
// AppDelegate または NSViewRepresentable 経由で NSWindow を取得後
window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.styleMask = [.borderless, .resizable]
window.isOpaque = false
window.backgroundColor = .clear
// Info.plist: LSUIElement = YES（Dockアイコン非表示）
```

- Mission Control では `.transient` を足して除外
- フルスクリーンアプリ使用中は非表示になるのが既定挙動（復帰時に自動再表示）
- メニューバーアイコンから「最前面化」モードをグローバルショートカットで提供し、キーボード操作の逃げ道を用意

### データモデル（JSON ファイルベース）

**保存先**: `~/TimeManager/` （ユーザーホーム直下、サンドボックス無効の前提）

**ファイル構成**:

```
~/TimeManager/
├── days/
│   ├── 2026-04-17.json    # 1日1ファイル
│   └── ...
├── tags.json              # 色タグ定義
├── settings.json          # 時間範囲、通知ON/OFF 等
└── trash/                 # ソフトデリートされたスロット（30日保持）
    └── 2026-04-17-<slot-id>.json
```

**1日ファイル (`days/YYYY-MM-DD.json`) のスキーマ**:

```json
{
  "date": "2026-04-17",
  "minSlotMinute": 600,
  "maxSlotMinute": 1140,
  "slots": [
    {
      "id": "<uuid>",
      "startAt": "2026-04-17T10:00:00+09:00",
      "endAt": "2026-04-17T11:00:00+09:00",
      "text": "A社提案書レビュー",
      "tagId": "dev",
      "originalBoundaries": []
    }
  ]
}
```

**tags.json / settings.json のスキーマ（抜粋）**:

```json
// tags.json
{
  "tags": [
    { "id": "dev", "name": "開発", "colorHex": "#4C9AFF", "order": 0 },
    { "id": "mtg", "name": "会議", "colorHex": "#F7B955", "order": 1 }
  ]
}

// settings.json
{
  "defaultStartMinute": 600,
  "defaultEndMinute": 1140,
  "notificationEnabled": true,
  "notificationIntervalMinutes": 30,
  "schemaVersion": 1
}
```

**設計ポイント**:

- スロットは「開始時刻が属する日」のファイルに保存
- 結合はスロット境界（`endAt`）の拡張で表現、`originalBoundaries` に元の境界を保持して分割時に復元
- 削除は `trash/` へ移動してソフトデリート（30日後に自動パージ）
- 書き込みは必ず `Data.write(to:options:.atomic)` でアトミック書き込み（クラッシュ時の破損防止）
- 並列書き込みはシリアル `DispatchQueue` または `actor` で直列化
- スキーマ変更は `settings.json` の `schemaVersion` を増やし、起動時マイグレーションで対応（JSONなので破壊的変更が少ない）
- ファイル破損検知時は `trash/` 同名ファイルの最新バックアップから復元を試みる（自動バックアップ戦略は後述）

**サンドボックス扱い**:

- `~/TimeManager/` へのアクセスはサンドボックスでは制限されるため、App Sandbox entitlement は **無効** で配布
- Mac App Store配布は行わない前提（Developer ID + Notarization の個人配布のみ）
- Notarization自体はサンドボックス無効でも通過可能

**代替候補（設定で切替可能にしておくか、ユーザーが変更したい場合）**:

- `~/Documents/TimeManager/` — Finder上で発見しやすいが、TCC（Documents Folderアクセス）の初回許可ダイアログが出る
- `~/Library/Application Support/TimeManager/` — 標準的なアプリデータ位置、TCC不要、ただしユーザーから見つけにくい

本計画ではデフォルトを `~/TimeManager/` とし、設定画面から保存ルートを変更可能にする（MVPでは変更UIは省略、`settings.json` の手動編集で対応可）。

### Visual Design Direction

**目標体験**: 「ウィンドウがある」ではなく「デスクトップに直接タイムラインが浮かんでいる」ように見える。記入済みスロットだけが半透明の角丸カプセルとして存在し、空の時間帯はほぼ透明で壁紙が透ける。

**基本方針（初期実装の出発点、反復で変更可）**:

- ウィンドウ自体は完全透過（`isOpaque = false`、`backgroundColor = .clear`、`.borderless`）
- 時刻ラベル（10:00, 10:30…）はテキストのみ、極薄のシャドウで壁紙に紛れないようにする
- 空スロット: 背景なし、ホバー時だけ薄いアウトラインで「ここ押せる」とわかる
- 記入済みスロット: `.ultraThinMaterial` ベースの角丸カプセル + 色タグのアクセント（左端の色バー or ドット）
- 現在時刻ライン: 赤の細い横線、左端に小さな丸マーカー
- フォーカス中（編集中）スロット: 少し濃い背景 + 微細な発光

**明示的に避けたいもの**:

- 「アプリのウィンドウっぽい」装飾（タイトルバー、枠線、影のついた矩形全体）
- 不透明な背景パネル
- 濃い色面やボタン風UI

**設計反復の前提**: 見た目は一度で決めない。Phase 2.5 で実際に動作するアプリの screenshot を壁紙バリエーション込みで確認しながら調整する。マテリアル種別・カプセルの角丸・パディング・タグ表現・空スロット表現は反復対象。

### 通知設計（UserNotifications）

- `UNCalendarNotificationTrigger` を曜日・時刻指定で30分毎にスケジュール
- クリック時は `UNNotificationResponse` → アプリ前面化 → 該当時刻スロットにスクロール + キャレット配置
- スリープ復帰後は直近1件のみ表示、それ以前は破棄
- 3回連続未応答でその日自動抑止（設定画面から再開）

## System-Wide Impact

### Interaction Graph

- **30分境界到達** → `NotificationScheduler` が `UNUserNotificationCenter` にローカル通知を積み、`CurrentTimeObserver` が現在時刻ラインを更新
- **通知クリック** → `AppDelegate` がアプリ前面化 → `WindowCoordinator` が背景固定ウィンドウを一時的に `.floating` に昇格 → `TimelineView` が該当時刻にスクロール + `TextField` にフォーカス → 数秒後 `.desktopIcon` に戻す
- **スロット編集コミット** → `SlotStore` が SwiftData に保存 → `DayBoundsRecalculator` が表示範囲を再計算 → `ExportFormatter` が次回エクスポート用のMarkdownを再生成
- **日付変更（0:00ローカル）** → `DayRollover` が `currentDay` を切替 → 現在日ビュー表示時のみ自動切替、過去日固定時は維持

### Error Propagation

- SwiftData保存失敗 → `SlotStore` が `Result<Void, PersistenceError>` を返却 → UI はトースト表示 + 編集中テキストをクリップボードに退避
- 通知許可拒否 → `NotificationScheduler.register()` が `.notAuthorized` を返却 → UI はバナーで「通知なしで利用可」を提示、コア機能は維持
- ウィンドウレベル設定失敗（Stage Manager等の新バージョンで挙動変化） → `WindowCoordinator` がフォールバックとして通常レベル + 低透過で表示し、メニューバーから再試行可能

### State Lifecycle Risks

- **編集中テキストの喪失**: フォーカス離脱・日付切替・アプリ終了前に必ず自動コミット。JSONはアトミック書き込みで中途半端なファイルが残らないようにする（テンポラリファイル → `rename(2)` での置換）
- **0:00跨ぎブロック**: 開始時刻基準で前日側に保存、UI上は「→続」マーカーで翌日側への継続を表示。自動分割はせず、見た目だけ分割（データ1件）
- **動的範囲拡張後のレコード全削除**: 当日限定でデフォルト範囲（10:00–19:00）へ自動復帰、過去日は保存された `minSlotMinute`/`maxSlotMinute` を維持
- **色タグ削除**: 使用中タグは削除不可、名称変更のみ許可（arcane な orphan を防ぐ）

### API Surface Parity

- 入力経路: 直接クリック編集・通知クリック経由フォーカス・メニューバーから「今のスロットに書く」ショートカットの3系統があるが、すべて `SlotStore.commit(slotId:text:tagId:)` に収束させ整合性を担保

### Integration Test Scenarios

1. **通知 → 背景固定ウィンドウ最前面化 → 編集 → 背景復帰** の一連フローがStage Manager有効/無効で成立すること
2. **0:00を跨いで編集中**に日付変更が起きたとき、未保存テキストが前日側にコミットされ翌日ビューに影響しないこと
3. **通知許可拒否状態**でも、タイムライン表示・入力・エクスポートが完全動作すること
4. **アプリ未起動状態**でmacOSの通知センターから直接通知クリックしたとき、正しくアプリ起動 + 該当スロットフォーカスまで到達すること
5. **JSONスキーマバージョン更新**を伴うアプリ更新で、既存ファイルのマイグレーションが動作すること（`schemaVersion` を増やした時に既存 `days/*.json` が新スキーマで読める）

## Implementation Phases

### Phase 1: 基盤とウィンドウ（MVP下地）

- Xcodeプロジェクト初期化（macOS 12+、SwiftUI、App Sandbox 無効）
- `NSWindow.Level.desktopIcon` + `collectionBehavior` で背景固定ウィンドウを表示
- Dockアイコン非表示（`LSUIElement = YES`）+ メニューバーアイコン追加
- アプリ再起動時のウィンドウ位置・サイズ復元（`UserDefaults`）
- **完了基準**: 他アプリを開いてもウィンドウが背面に留まり、メニューバーから表示ON/OFFできる

### Phase 2: タイムライン表示と基本入力

- 10:00–19:00の30分スロットを縦型表示、現在時刻を赤ラインで表示
- スロットクリックでインライン `TextField` 展開、`Enter`で保存 / `Esc`で破棄 / `Cmd+Z`でUndo
- 色タグ5種のプリセット（開発/会議/休憩/調査/その他）とタグ選択UI
- `~/TimeManager/` 配下のファイル構造初期化（起動時に `days/` `trash/` `tags.json` `settings.json` を自動生成）
- JSONファイルリポジトリ層（`DayFileStore` / `TagStore` / `SettingsStore`）と `SlotStore`（高レベルAPI）実装
- アトミック書き込み（一時ファイル → `FileManager.replaceItem`）
- **ビジュアル初期実装**: 後述「Visual Design Direction」に従い、透過ウィンドウ + 半透明カプセルを仮実装
- **完了基準**: 1日分のスロット入力・編集・色タグ付与が `~/TimeManager/days/YYYY-MM-DD.json` に保存され、再起動後も残る。Finderでファイルを直接開いて内容が読めること

### Phase 2.5: ビジュアルデザイン反復

Phase 2の機能が動作した後、screenshotを見ながらデザインを複数回イテレーションする。機能実装と分離して明示的にフェーズを確保することで、実物を見ずに紙上でデザインを決め込まないようにする。

- 実機で複数の壁紙（明るい/暗い/ごちゃついた写真）に対して表示確認
- カプセルの背景素材（`.ultraThinMaterial` / 半透明ダーク / ライト）、コーナー半径、影、パディングを調整
- 空スロットの視認性（完全透明 vs 極薄罫線 vs ホバー時のみ表示）を評価
- 現在時刻ライン・時刻ラベル・日付ヘッダーの強度バランス
- 色タグの見え方（カプセル全体 / 左端バー / ドットのみ）を複数案比較
- フォント・サイズ・行間の微調整
- **完了基準**: 「透過ウィンドウにタイムラインが浮かんでいる」体験として納得感がある。主要な壁紙パターンで読みやすさが担保される

### Phase 3: スロット操作とタイムライン拡張

- 隣接スロット結合/分割（端ドラッグでリサイズ、長押しで分割）
- 同タグ隣接スロットの自動マージ（オプション、設定でON/OFF）
- 時間範囲の動的伸縮（記録範囲に応じて自動拡張、当日削除で復帰）
- 過去日ナビゲーション（前日/翌日ボタン + 日付ピッカー + `←`/`→`キー）
- 未入力スロットのハッチ表示
- **完了基準**: 同じ作業で1時間続けた場合に1ブロックとして扱える、過去の日を遡って閲覧できる

### Phase 4: 通知・オンボーディング・エクスポート

- 30分ごとの `UNCalendarNotificationTrigger` ローカル通知（ON/OFF切替、3回未応答で当日抑止）
- 通知クリックで該当スロットにフォーカス
- 初回起動時のオンボーディング（通知許可 → 時間範囲確認 → タグ初期5種 → 自動起動ON）
- 現在表示日のMarkdownクリップボードコピー（`## HH:MM–HH:MM [タグ] テキスト` 形式）
- **完了基準**: 通知から1クリックで記入までたどり着ける、日報にそのまま貼れるMarkdownが取れる

### Phase 5: データ保護・配布

- ソフトデリート + 30日保持 + ゴミ箱UI（`~/TimeManager/trash/` への移動 + 復元 + 自動パージ）
- 週次で `~/TimeManager/backups/` に ZIP 形式の全データスナップショット自動書き出し（過去4週分をローテーション保持）
- Developer ID署名 + Notarization（App Sandbox は無効のまま Notarization 通過確認）
- Sparkle 2.x による自動更新
- メニューバーから「データフォルダをFinderで開く」導線（`~/TimeManager/` を一発で開ける）
- **完了基準**: 誤削除から30日以内に復元でき、署名済み `.app` を個人配布できる。ユーザーがFinderで `~/TimeManager/` を開いてデータを閲覧・コピーできる

### Phase 6 (Post-MVP): 拡張候補

- エクスポートテンプレートのカスタマイズ、ファイル出力、週/月単位出力
- アクセシビリティ強化（VoiceOver rotor、Dynamic Type、色タグへのアイコン併記）
- 色タグのユーザー追加/色変更
- キーボード完全操作（グローバルショートカットで最前面化 → Tabフォーカス移動）
- 集中モード連動での通知自動スヌーズ

## Acceptance Criteria

### Functional Requirements

- [x] **R1 背景固定**: `NSWindow.Level.desktopIcon + 1` と `[.canJoinAllSpaces, .stationary, .ignoresCycle, .transient]` で実装（ユーザーによる実機検証は `.app` ビルド後に実施）
- [x] **R2 時間範囲**: 既定 10:00–19:00。`SlotStore.ensureSlotGrid()` が 0:00–24:00 まで自動拡張。当日で空なら既定範囲に復帰
- [x] **R3 結合/分割**: `mergeWithNext` / `split` / `resize(±30分)` を SlotStore に実装、コンテキストメニューから呼べる。`originalBoundaries` 保持で分割時に元境界に復元
- [x] **R4 内容**: 自由記述テキスト + `TagStripPicker` でプリセット色タグ 1つ付与（開発/会議/休憩/調査/その他）
- [x] **R5 入力タイミング**: 空スロットクリックで即編集、過去スロットも同 UI で編集可
- [x] **R6 通知**: `UNCalendarNotificationTrigger` で毎時 :00 と :30 に繰り返し配信。メニューから ON/OFF、通知クリックで前面化 + 該当スロット生成
- [x] **R7 過去日**: 前日/翌日ボタン + `DatePickerSheet` + 矢印キー。当日でなければ「過去」バッジ表示
- [x] **R8 エクスポート**: メニューバーから「今日を Markdown でコピー」(`MarkdownExporter`) でクリップボードへ

### Non-Functional Requirements

- [x] 作業切り替えからスロット記録完了まで30秒以内で完結するUX（クリック→テキスト入力→Enter の2ステップ）
- [x] macOS 12以降で動作（deploymentTarget 12.0、`Codable` + `FileManager` ベースの永続化）
- [x] アプリ起動直後から1秒以内にタイムラインが表示される（非同期ロードなし、`NSHostingView` 直接 mount）
- [ ] Developer ID + Notarization済みの `.dmg` / `.zip` を個人配布できる ※ Phase 5 別セッションで対応

### Edge Case Coverage (from SpecFlow)

- [x] 0:00を跨ぐブロックは開始時刻の日に所属、UI上の終端は「24:00」扱い（Markdown/表示共通）
- [x] 編集中のテキストは `onSubmit`/フォーカス離脱時に `SlotStore.commit` へ集約、日付切替/アプリ終了はフォーカス離脱をトリガに保存
- [x] 通知許可拒否時も `rescheduleAll` 以外の全機能が動作（オンボーディングで許諾拒否しても onboardingCompleted は記録される）
- [x] `collectionBehavior` に `.canJoinAllSpaces, .stationary, .ignoresCycle, .transient` を付与しマルチ Space / Stage Manager / Mission Control に対応
- [x] フルスクリーン終了後の再表示は `.transient` + Space Join で OS が自動復帰
- [ ] 削除は30日ソフトデリート（`trash/` への移動は実装済、自動パージは Phase 5 で対応）
- [x] `~/TimeManager/` のファイルはユーザーが Finder で直接開いて閲覧可能（メニュー「データフォルダを Finder で開く」で一発アクセス）
- [x] JSON書き込みは `AtomicFileWriter`（一時ファイル → `FileManager.replaceItemAt`）でアトミック

### Quality Gates

- [x] xcodebuild でビルド成功（warning 0）、`xcodebuild test` で 6/6 パス
- [ ] 「Integration Test Scenarios」5項目の実機確認は `.app` ビルド後のユーザー検証待ち
- [x] JSONマイグレーション経路: `AppSettings.schemaVersion` で将来の破壊的変更に備える枠を用意

## Success Metrics

- **継続率**: 導入後2週間で80%以上の日で1件以上記録がある
- **入力摩擦**: 1スロット記録の所要時間の中央値が30秒以下
- **日報流用**: エクスポート機能が週5回以上使われる（個人用途のため計測は自己申告ベース）
- **通知ON継続率**: 通知機能を有効にしたユーザーが2週間後も有効のまま（OFFにしたくなるほど煩雑でない）

## Dependencies & Risks

### Dependencies

- macOS 12以降（`Codable` + `FileManager` による永続化のため、SwiftData不使用）
- Apple Developer Program加入（$99/年、Developer ID署名とNotarizationのため）
- Sparkle 2.x（EdDSA署名対応、自動更新）
- App Sandbox は無効（`~/TimeManager/` へアクセスするため。Mac App Store配布はしない前提）

### Risks

| リスク | 影響 | 緩和策 |
|---|---|---|
| Stage Manager/Mission Control のメジャーアップデートで `collectionBehavior` の挙動が変化する | 背景固定が崩れる | フォールバックとして `.floating + 低透過` + メニューバーから手動再配置を常備 |
| `UNCalendarNotificationTrigger` の配信信頼性（スリープ・Focus Mode中） | 通知が来ない | OS委譲が前提。3回連続未応答抑止ロジックでノイズ化を防ぎ、未入力スロットのUI強調で補完 |
| JSONスキーマ変更時のデータ読み込み破綻 | バージョンアップで既存データが開けない | `settings.json.schemaVersion` によるマイグレーション。`Codable` のオプショナル新フィールド追加は後方互換で安全、破壊的変更時は起動時マイグレーションで旧ファイルを `backups/` に退避してから書き換え |
| ユーザーが `~/TimeManager/` を意図せず削除・移動 | データ消失 | 起動時にフォルダ不在を検知したら警告 + 最新 `backups/` ZIP からの復元UIを提示 |
| アトミック書き込み失敗（ディスク満杯等） | 書き込みエラー・編集内容喪失 | `FileManager.replaceItem` のエラーハンドリング、失敗時は編集中テキストをクリップボードに退避しトースト表示 |
| 個人配布時のアップデート離脱 | 古いバージョンが残る | Sparkle で自動更新を既定ON |
| Appleシリコン/Intelのビルド分け | 配布物が増える | Universal Binary で単一 `.app` にする |

## Sources & References

### Origin

- **Origin document**: [docs/brainstorms/2026-04-17-desktop-timeline-manager-requirements.md](../brainstorms/2026-04-17-desktop-timeline-manager-requirements.md)
- **Key decisions carried forward**:
  - デスクトップ背景固定型ウィンドウ（常に視界の隅、入力の心理的コストを最小化）
  - 30分スロット + 結合可能（固定粒度の負荷を下げつつ柔軟さを確保）
  - 色タグ + テキスト（集計は不要だが視認性のため最小構造で採用）
  - 時間範囲の動的伸縮（早朝・残業対応とシンプルさの折衷）

### Internal References

- 新規プロジェクト（既存コードなし）
- `README.md` は空

### External References

- NSWindow Levels: Apple Developer Documentation（`NSWindow.Level`、`CGWindowLevelForKey`、`collectionBehavior`）
- UserNotifications framework: `UNCalendarNotificationTrigger` 公式リファレンス
- SwiftData: Apple公式ドキュメント（macOS 14+）
- Sparkle 2.x: <https://sparkle-project.org/>（EdDSA署名、個人配布での業界標準）
- Notarization: `xcrun notarytool` ガイド
- Toggl / Timing for Mac / Sorted / Clockify の UX パターン調査（本計画の SpecFlow 入力に反映済み）

### Related Work

- SpecFlow解析結果（本計画の Edge Case Coverage に反映済み）
- 技術選定リサーチ（Swift/SwiftUI、Electron、Tauri 2.x の比較）

## Outstanding Questions (from origin, resolved or deferred)

| 項目 | ステータス | 本計画での対応 |
|---|---|---|
| デスクトップ背景固定の実装方式 | ✅ 解決 | Swift/SwiftUI + `NSWindow.Level.desktopIcon` を採用 |
| 色タグのプリセット / カスタマイズ範囲 | 🔶 部分解決 | MVPは5種固定（開発/会議/休憩/調査/その他）、追加カスタマイズは Phase 6 |
| スロット結合/分割の操作UI | ✅ 解決 | 端ドラッグでリサイズ + 長押しで分割 |
| 過去日ナビゲーションUI | ✅ 解決 | 前日/翌日ボタン + 日付ピッカー + 矢印キー |
| 日報エクスポート仕様 | ✅ 解決（MVP） | 現在表示日のMarkdownクリップボードコピー |
| ローカルデータ保存形式・場所 | ✅ 解決 | `~/TimeManager/` 配下に1日1ファイルのJSON。App Sandbox無効、`~/TimeManager/backups/` に週次ZIPスナップショット |
| 通知のデフォルトON/OFF・アプリ未起動時 | ✅ 解決 | 既定ON、`UNCalendarNotificationTrigger` でアプリ未起動でもOS配信 |
| 時間範囲拡張の上限 | ✅ 解決 | 0:00–24:00 |
