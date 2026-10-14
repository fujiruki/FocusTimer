# 002 XcodeGenとGitHub Actionsでビルドし、未署名IPAを作る

- 状態: 採用
- 日付: 2026-10-14
- 関連コミット: `6b0ab8e`, `119fc9b`, `bb78aa6`, `4d77674`
- 関連: spec/05_技術設計.md

## 背景

手元にMacもXcodeもない。iOSアプリのビルドにはmacOSとXcodeが必要。

## 決定

- プロジェクトは XcodeGen の `project.yml` で定義する。`.xcodeproj` と生成される `Info.plist` はコミットしない（`.gitignore` で除外）。
- ビルドは GitHub Actions のmacOSランナーで行う。手順は次のとおり。
  1. XcodeGenでプロジェクトを生成する
  2. シミュレーターでXCTestを実行する
  3. 実機用に署名なしでビルドする
  4. `Payload/` に入れてzipにし、`.ipa` にする
- 署名とインストールだけを、Windows・iPhone側で行う（ADR-003）。

## 理由

- `.xcodeproj` は手で編集しにくく、差分も読めない。YAMLならWindowsで編集・レビューできる。
- 署名を手元で行う形にすると、Apple IDの情報をCIに置かずに済む。
- シミュレーターでテストを回せば、Macがなくてもロジックのテストができる。

## 根拠・調査

- 初回のビルドは修正なしで成功した。
- CIで追加したテストが落ちたことから、初期化中に `didSet` の補正が働く不具合が見つかった（`4d77674`）。Windowsだけでもユニットテストまで回せることを確認できた。
- シミュレーターは機種名ではなく `simctl list -j` のJSONから選ぶ（`bb78aa6`）。Codexのレビューで、機種名に括弧があると選び間違える、と指摘されたため。
- `actions/checkout` と `upload-artifact` はv5にした。Node.js 20 が非推奨になったという警告が出たため。

## 影響・残るリスク

- WAVを追加したときにpushがHTTP 408で失敗した。以降は `git -c http.postBuffer=524288000 push` を使う。
- GitHubからworkflowファイルをpushするには、`gh` の `workflow` スコープが必要（`gh auth refresh -h github.com -s workflow`）。
