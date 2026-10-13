# Mouse Light Off

対応するロジクール製マウスの装飾ライトをまとめて消灯する、macOSメニューバーアプリです。Swift / AppKit / IOKitだけで動作し、G HUB・OpenRGB・Homebrew・外部ライブラリは不要です。

[ダウンロード](https://github.com/foxode-app/mouse-light-off/releases/tag/v0.2.2) · [製品ページ](https://foxode.com/products/mouse-light-off/) · [不具合報告](https://github.com/foxode-app/mouse-light-off/issues)

## 対応対象

USB有線接続の次の8機種を対象にしています。接続時に照明機能・ゾーン・エフェクトを照会し、互換性を確認できた機器だけを制御します。

| 機種 | USB PID | 実機確認 |
|---|---|---|
| G403 HERO | C08F | 専用版および汎用版0.2.1でユーザーが消灯を確認済み |
| G403 Prodigy | C083 | 未検証 |
| G203 Prodigy | C084 | 未検証 |
| G303 Daedalus Apex | C080 | 未検証 |
| G502 Proteus Spectrum | C332 | 未検証 |
| G502 HERO | C08B | 未検証 |
| G PRO（有線） | C085 | 未検証 |
| G PRO HERO（有線） | C08C | 未検証 |

ベンダーIDはすべて `046d` です。G203 LIGHTSYNC、G502 X PLUS、G600、無線レシーバー、Bluetooth、他社製マウスは対象外です。製品名が似ていてもPIDが異なる場合は制御しません。G403 HERO以外の7機種は公開実装に基づく実験対応です。G403 HEROは汎用版0.2.1でもユーザーが手動消灯を確認しています。0.2.1ではスリープ後の自動再消灯に取りこぼしが報告され、0.2.2で復帰処理を改善しています。配布はプレビュー版として扱います。

## 必要環境

- macOS 13以降。現在のビルドはApple Silicon向けです。
- ビルドにはフル版Xcodeが必要です。パッケージ定義のSwift tools versionは5.9で、フォーマット・lintには `swift format` を同梱したツールチェーンが必要です。検証環境はXcode 27.0 / Swift 6.4です。システムのXcode選択設定は変更しません。
- 初回はmacOSの「入力監視」でMouse Light Offの許可が必要です。

## ダウンロード版のインストール

1. [GitHub Releases](https://github.com/foxode-app/mouse-light-off/releases/tag/v0.2.2)から `Mouse-Light-Off-0.2.2-arm64.dmg` をダウンロードして開き、`Mouse Light Off.app` を「アプリケーション」にコピーします。GitHubが自動生成する「Source code」は開発用のソースです。
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

「起動時・再接続・復帰時に自動消灯」を有効にすると、起動時、USB再接続、本体・画面のスリープ復帰、ユーザーセッションの復帰、ロック解除をきっかけに消灯を再適用します。既存の自動消灯設定を引き継ぎます。

復帰直後の通信準備や遅れて起こるマウス側のリセットに備え、通知から0.5・2・5・10・20秒後を目安に、最大5回、接続を取り直して消灯します。最初の消灯に応答があっても後続の再適用を行います。通信処理中は次の操作を待機させ、期限を過ぎた複数の予約は1回にまとめます。通知が続いても同じ再適用期間を延長せず、無期限の定期通信は行いません。

自動消灯をオフにすると予約済みの再適用を取り消します。本体・画面のスリープ、画面ロック、セッション離脱、アプリ終了時も予約を取り消し、進行中の消灯は通信命令の区切りで停止します。「すべて点灯（白）」も保留中の自動消灯を取り消し、直後に予約処理で消されることを防ぎます。自動消灯の設定自体は維持するため、次の復帰や再接続では自動消灯が再開します。

スリープ中やログアウト中にアプリが動作できない場合、マウス側で点灯すること自体は防げません。通信が利用できる復帰後に再消灯する機能です。本体の永続プロファイルやMacのスリープ・ロック設定は変更しません。

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

`Sources/MouseLighting/` は対応表・USB通信・HID++パケット、`Sources/MouseLightOff/` は画面と接続通知、`Tests/MouseLightingTests/` はパケット・能力照会・複数機器処理の検証、`Tests/MouseLightOffTests/` は復帰時の再適用・取消とメニューバー画像の描画検証、`Resources/` はアプリ情報とアイコン、`scripts/` はビルド用です。外部依存がないため依存関係ロックファイルは生成されません。Swift標準formatterを使います。

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

## 復帰処理の実装と診断

本体・画面・セッションの復帰には `NSWorkspace` の通知を使用します。ロック解除は `DistributedNotificationCenter` の `com.apple.screenIsUnlocked` を補助的に監視します。アプリが非アクティブでも保留されないよう、分散通知は `.deliverImmediately` で登録します。この通知名はAppleの公開API契約ではないため、通常のスリープ復帰は公開されているWorkspace通知だけでも再適用できるようにしています。

[Appleの画面復帰通知](https://developer.apple.com/documentation/appkit/nsworkspace/screensdidwakenotification)と、同じロック通知を利用する[Electronの実装](https://github.com/electron/electron/blob/main/shell/browser/api/electron_api_power_monitor_mac.mm)を参照してください。

macOSの統合ログに、再適用を始めた理由・試行番号・結果を記録します。通常のキー入力やマウス操作の内容は記録しません。ログは次のコマンドで確認できます。

```sh
log show --last 10m --info --style compact --predicate 'subsystem == "com.foxode.mouselightoff.app" AND category == "AutoOff"'
```

## 検証結果（2026-10-13）

- G403専用版および汎用版0.2.1での手動消灯をユーザーが実機確認済み。0.2.2では、インストール済みアプリの起動後にG403 HEROの2照明ゾーンが5回すべての消灯命令に正常応答することを確認しました。
- `make test` で42件の自動テスト成功（MouseLighting 25件、MouseLightOff 17件）。1〜3ゾーン、動的な効果番号、非対応時の書き込み防止、RAMのみへの適用、不正応答・機器エラー、複数マウスとインターフェース重複排除、メニューバー画像の描画を検証。今回追加した18件では、復帰通知、有限回の再適用、通知の集約、通信失敗、手動操作・設定無効化・スリープ・終了時の取消、古い完了通知の無視、HID++命令間の取消を検証しました。
- アプリ非アクティブ時の分散通知配送を独立した通知名で実測し、`.deliverImmediately` による即時配送を確認しました。
- `make lint`、Releaseビルド、Developer ID署名、Apple公証、DMGへのチケット添付、DMGと内部アプリのGatekeeper検証成功。インストール済みアプリのバージョン・署名・配布用バイナリとの一致も確認しました。
- 0.2.2での実際のスリープ・画面復帰・ロック解除を通した実機動作、白色点灯、USB再接続、G403以外の実機、macOS 13実機は未検証です。

通信仕様の根拠と参照元は [docs/PROTOCOL.md](docs/PROTOCOL.md) を参照してください。Mouse Light OffはFoxodeの独立したプロジェクトで、Logitech / ロジクールの公式製品ではありません。

## ライセンス

[MIT License](LICENSE)。Copyright (c) 2026 Foxode.
