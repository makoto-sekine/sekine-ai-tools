# MeetingRecorder

macOSでミーティング音声を自動録音するメニューバーアプリです。Zoom、Teams、Google Meetなどのミーティングアプリを検知して自動的に録音を開始します。

## 特徴

- **BlackHole不要**: macOSのScreenCaptureKitを使用してシステム音声を直接キャプチャ
- **自動検知**: Zoom、Teams、WebEx等のミーティングアプリを検知して自動録音開始
- **メニューバー常駐**: 軽量なメニューバーアプリとして動作
- **MP3出力**: ffmpegがインストールされていればMP3、なければM4A/WAVで保存

## システム要件

- macOS 13.0 (Ventura) 以上
- Xcode 15.0 以上（ビルド用）

## セットアップ

### 1. リポジトリのクローン

```bash
cd /Users/m.sekine/work/業務効率化ツール/MeetingRecorder
```

### 2. Xcodeでビルド

```bash
# Swift Package Managerでビルド
swift build -c release

# または Xcodeで開く
open Package.swift
```

### 3. MP3出力を有効にする（オプション）

MP3形式で保存したい場合は、ffmpegをインストールしてください：

```bash
brew install ffmpeg
```

ffmpegがない場合は、M4A（AAC）またはWAV形式で保存されます。

## 権限設定

初回起動時に以下の権限を許可する必要があります：

### 画面収録の許可（システム音声の録音に必要）

1. システム設定を開く
2. プライバシーとセキュリティ → 画面収録
3. MeetingRecorderを追加して許可

### マイクの許可

1. システム設定を開く
2. プライバシーとセキュリティ → マイク
3. MeetingRecorderを追加して許可

## 使い方

### 基本操作

1. アプリを起動するとメニューバーにマイクアイコンが表示されます
2. アイコンをクリックしてメニューを開きます

### 手動録音

- メニューから「録音開始」をクリック
- 録音中は「録音停止」をクリックして停止

### 自動録音

- 「自動検知: ON」の状態でミーティングアプリを起動
- Zoom、Teams等が検知されると自動的に録音開始
- アプリを終了すると自動的に録音停止

### 録音ファイルの確認

- メニューから「録音フォルダを開く」をクリック
- 保存先: `~/Documents/MeetingRecordings/`

## 対応ミーティングアプリ

| アプリ | 自動検知 |
|--------|----------|
| Zoom | ✅ |
| Microsoft Teams | ✅ |
| WebEx | ✅ |
| FaceTime | ✅ |
| Skype | ✅ |
| Slack | ⚠️ （起動のみ検知） |
| Discord | ⚠️ （起動のみ検知） |
| Google Meet | ⚠️ （ブラウザ経由） |

※ ブラウザベースのミーティング（Google Meet等）は現在自動検知の対象外です。手動で録音を開始してください。

## プロジェクト構造

```
MeetingRecorder/
├── Package.swift                           # Swift Package Manager設定
├── MeetingRecorder/
│   ├── MeetingRecorderApp.swift           # アプリエントリーポイント
│   ├── AppDelegate.swift                  # メニューバーUI管理
│   ├── AudioCapture/
│   │   ├── RecordingManager.swift         # 録音全体の管理
│   │   ├── SystemAudioCapture.swift       # システム音声キャプチャ
│   │   ├── MicrophoneCapture.swift        # マイク入力キャプチャ
│   │   └── AudioMixer.swift               # 音声ミキシング
│   ├── MeetingDetector/
│   │   └── MeetingAppDetector.swift       # ミーティングアプリ検知
│   └── Export/
│       └── AudioExporter.swift            # 音声ファイル出力
├── Resources/
│   └── Info.plist                         # アプリ設定・権限
└── README.md
```

## 技術詳細

### 使用フレームワーク

- **ScreenCaptureKit**: システム音声のキャプチャ（macOS 12.3+）
- **AVFoundation**: マイク入力のキャプチャ
- **NSWorkspace**: 実行中アプリの監視
- **AppKit/SwiftUI**: メニューバーUI

### 音声処理フロー

```
システム音声 (ScreenCaptureKit)
         ↓
    AudioMixer  ←  マイク入力 (AVAudioEngine)
         ↓
   AVAudioFile (WAV一時保存)
         ↓
   ffmpeg変換 (MP3) または AVAssetExportSession (M4A)
         ↓
   最終出力ファイル
```

## トラブルシューティング

### 「画面録画の権限が必要です」と表示される

1. システム設定 → プライバシーとセキュリティ → 画面収録
2. MeetingRecorderにチェックを入れる
3. アプリを再起動

### 録音ファイルに音声が入っていない

- システム出力（スピーカー/ヘッドフォン）から音が出ていることを確認
- マイクが正しく接続されていることを確認
- システム設定でデフォルトのマイクが選択されていることを確認

### 自動検知が動作しない

- 「自動検知: ON」になっていることを確認
- 対応アプリ一覧を確認（ブラウザベースのミーティングは対象外）

## ライセンス

MIT License

## 参考

- [ScreenCaptureKit - Apple Developer](https://developer.apple.com/documentation/screencapturekit/)
- [Azayaka](https://github.com/Mnpn/Azayaka) - ScreenCaptureKit使用例
- [MeetingBar](https://github.com/leits/MeetingBar) - Swift製ミーティング検知アプリ
