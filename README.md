# Mouse Light Off

対応するロジクール製マウスの装飾ライトをまとめて消灯する、macOSメニューバーアプリです。Swift / AppKit / IOKitだけで動作し、G HUB・OpenRGB・Homebrew・外部ライブラリは不要です。

[ダウンロード](https://github.com/foxode-app/mouse-light-off/releases/tag/v0.2.1) · [製品ページ](https://foxode.com/products/mouse-light-off/) · [不具合報告](https://github.com/foxode-app/mouse-light-off/issues)

## 対応対象

USB有線接続の次の8機種を対象にしています。接続時に照明機能・ゾーン・エフェクトを照会し、互換性を確認できた機器だけを制御します。

| 機種 | USB PID | 実機確認 |
|---|---|---|
| G403 HERO | C08F | 旧G403専用版でユーザーが消灯を確認済み |
| G403 Prodigy | C083 | 未検証 |
| G203 Prodigy | C084 | 未検証 |
| G303 Daedalus Apex | C080 | 未検証 |
| G502 Proteus Spectrum | C332 | 未検証 |
| G502 HERO | C08B | 未検証 |
| G PRO（有線） | C085 | 未検証 |
| G PRO HERO（有線） | C08C | 未検証 |

ベンダーIDはすべて `046d` です。G203 LIGHTSYNC、G502 X PLUS、G600、無線レシーバー、Bluetooth、他社製マウスは対象外です。製品名が似ていてもPIDが異なる場合は制御しません。G403 HERO以外の7機種は公開実装に基づく実験対応です。G403 HEROも、この汎用版での実機確認はまだ行っていません。初回配布はベータ版として扱います。

## 必要環境

- macOS 13以降。現在のビルドはApple Silicon向けです。
- ビルドにはフル版Xcodeが必要です。パッケージ定義のSwift tools versionは5.9で、フォーマット・lintには `swift format` を同梱したツールチェーンが必要です。検証環境はXcode 27.0 / Swift 6.4です。システムのXcode選択設定は変更しません。
- 初回はmacOSの「入力監視」でMouse Light Offの許可が必要です。

## ダウンロード版のインストール

1. [GitHub Releases](https://github.com/foxode-app/mouse-light-off/releases/tag/v0.2.1)から `Mouse-Light-Off-0.2.1-arm64.dmg` をダウンロードして開き、`Mouse Light Off.app` を「アプリケーション」にコピーします。GitHubが自動生成する「Source code」は開発用のソースです。
2. コピーしたアプリを開き、設定画面の「アクセス許可を要求」を押します。
3. 「システム設定 → プライバシーとセキュリティ → 入力監視」で **Mouse Light Off** を許可します。表示されない場合は「＋」で「アプリケーション」内のアプリを追加します。
4. アプリを終了して開き直し、「接続を確認」で認識状態を確認します。その後「すべて消灯」を押します。

起動中はメニューバーにマウスのアイコンを表示します。設定画面を閉じても常駐し、アイコンから設定を開き直せます。終了するにはメニューの「Mouse Light Offを終了」、または設定画面の「アプリを終了」を押してください。Dockには常駐しません。

macOSの確認画面の文言はOSのバージョンによって異なります。アクセシビリティ・フルディスクアクセスの許可は不要です。Developer IDで署名・公証された配布版でも入力監視の許可は必要です。

更新時はアプリを終了し、「アプリケーション」の既存アプリを置き換えます。0.2.0以前でアイコンが見えない場合は、アクティビティモニタで `Mouse Light Off` を検索して終了してください。0.2.1でメニューバーのアイコンが表示されない不具合を修正しています。自動更新機能はありません。アドホック署名の開発版から初めて配布版に移行する際は、入力監視の項目を削除して追加し直す必要がある場合があります。

## ローカルビルドと起動

```sh
git clone https://github.com/foxode-app/mouse-light-off.git
cd mouse-light-off
make test
make lint
make app
open "build/Mouse Light Off.app"
```

継続して使用する場合は、アプリを終了してからFinderで `/Applications` にコピーし、そのコピーを開いてください。権限の設定は配置先を決めてから行ってください。`make app` の既定値はローカル実行用のアドホック署名で、一般配布用ではありません。

Xcodeを標準以外の場所に置いている場合は、各コマンドの前に `DEVELOPER_DIR='/path/to/Xcode.app/Contents/Developer'` を指定してください。ソースからのローカルビルドにApple DeveloperアカウントやAPIキーは不要です。

## Developer IDによる配布ビルド

キーチェーンにDeveloper ID Application証明書と対応する秘密鍵を用意し、証明書名またはSHA-1ハッシュを `SIGNING_IDENTITY` に指定します。

```sh
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' make app
codesign --verify --strict --verbose=2 'build/Mouse Light Off.app'
codesign --display --verbose=4 'build/Mouse Light Off.app'
```

ビルドはApple Silicon（arm64）固定、最低OSはmacOS 13です。Developer IDを指定した場合は `--options runtime --timestamp` で署名します。一般配布時は、署名済みアプリをDMGに入れ、DMGにも署名してAppleへ公証申請します。配布するDMGに公証チケットをステープルし、Gatekeeperの検証を済ませてから公開してください。[Appleの配布手順](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)を参照してください。実機検証では、既存の自動消灯設定が有効だと起動時に消灯する点にも注意してください。

この直接配布版はApp Sandboxを使用しません。Hardened Runtimeの例外を必要とするJIT・外部プラグイン等も使っていないため、追加のentitlementsはありません。USB用の `com.apple.security.device.usb` はApp Sandbox用で、この構成では追加しません。入力監視は `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` で要求し、許可を確認してから照明通信を行います。

根拠：[AppleのHardened Runtime設定](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime)、[USB entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.usb)、[IOHIDRequestAccess](https://developer.apple.com/documentation/iokit/3181574-iohidrequestaccess)。

## 操作

メニューバーから設定画面を開き、「すべて消灯」または「すべて点灯（白）」を押します。接続された対応機種ごとに成功・失敗を表示します。複数台の同じ機種も区別して処理します。「点灯（白）」は白色の固定点灯で、変更前の色やアニメーションを復元する機能ではありません。

画面の「アクセス許可を要求」を押し、「システム設定 → プライバシーとセキュリティ → 入力監視」で **Mouse Light Off** を許可し、アプリを終了して開き直してください。照明用通信に使うHIDインターフェースがmacOSの入力監視の対象になるため必要です。通常のキー・マウス入力は保存せず、照明命令のHID++応答のみ処理します。

旧「G403 Light Control」とはアプリ識別子が異なるため、権限の再許可が必要になる場合があります。自動消灯の設定は初回起動時に旧アプリから引き継ぎます。旧アプリを終了してから新アプリを使用してください。

「起動時・再接続時に消灯」は任意で有効にできます。USB接続通知とスリープ復帰通知を使って再適用します。自動適用を無効にしても、消えているライトを点灯させる操作は行いません。

## 設定の保持

消灯はRAM上の照明設定に適用します。本体の永続プロファイル・DPI・ボタン割り当ては書き換えません。USBを抜く、電源が切れるなどすると照明が戻る可能性があります。自動消灯はアプリの実行中のみ働きます。ログイン時の起動は、macOSの「一般 → ログイン項目」に配置済みのアプリを追加してください。

## 開発

```sh
make build
make test
./scripts/swift-env.sh xcrun swift test --filter LightingCommandsTests
make format
make lint
make app
```

`Sources/MouseLighting/` は対応表・USB通信・HID++パケット、`Sources/MouseLightOff/` は画面と接続通知、`Tests/MouseLightingTests/` はパケット・能力照会・複数機器処理の検証、`Tests/MouseLightOffTests/` はメニューバー画像の描画検証、`Resources/` はアプリ情報とアイコン、`scripts/` はビルド用です。外部依存がないため依存関係ロックファイルは生成されません。Swift標準formatterを使います。

アプリアイコンは `scripts/create-icon.swift` がAppKitの図形描画で生成したものです。通常のビルドでは同梱の `Resources/MouseLightOff.icns` を使います。PNGを再生成する場合は次のコマンドを使ってください。

```sh
mkdir -p build
./scripts/swift-env.sh xcrun swift scripts/create-icon.swift build/MouseLightOff.png
```

変更前後に `make test` と `make lint` を実行してください。新機種の提案にはUSB VID/PID、接続方法、macOSバージョン、`--inspect` の結果、実機での確認内容を記載してください。機器のシリアル番号など、個人情報は削除してから共有してください。証明書・秘密鍵・トークン・ローカル設定・生成した配布物をリポジトリへ追加しないでください。

```sh
"build/Mouse Light Off.app/Contents/MacOS/MouseLightOff" --supported
"build/Mouse Light Off.app/Contents/MacOS/MouseLightOff" --inspect
"build/Mouse Light Off.app/Contents/MacOS/MouseLightOff" --off
"build/Mouse Light Off.app/Contents/MacOS/MouseLightOff" --white
```

`--supported` は対応表を表示するだけです。`--inspect` は問い合わせのみで、照明を変更しません。コマンドラインからの実行は起動元に別途入力監視の許可が必要な場合があります。タイムアウト時はG HUBやOpenRGBとの競合、USB接続、権限を確認してください。

## 検証結果（2026-10-13）

- G403専用版での消灯をユーザーが実機確認済み。
- 汎用版は24件の自動テスト成功。1〜3ゾーン、動的な効果番号、非対応時の書き込み防止、RAMのみへの適用、不正応答・機器エラー、複数マウスとインターフェース重複排除を検証。メニューバー画像はSF Symbolsの解決・描画と、シンボルが使えない場合の代替描画を検証。
- `make lint`、Releaseビルド、アドホック署名検証成功。
- 新しい汎用版の実機消灯・白色点灯・USB再接続・スリープ復帰、G403以外の実機、macOS 13実機は未検証。

通信仕様の根拠と参照元は [docs/PROTOCOL.md](docs/PROTOCOL.md) を参照してください。Mouse Light OffはFoxodeの独立したプロジェクトで、Logitech / ロジクールの公式製品ではありません。

## ライセンス

[MIT License](LICENSE)。Copyright (c) 2026 Foxode.
