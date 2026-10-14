# フォーカスタイマー（Macなし SwiftUI 最小試作）

## 仕様
正本は `docs/SPEC.md`（SdDD）。原典はカンガルー `2026-10-13_02_…要件・仕様案_引き継ぎ.md` と `2026-10-14_03_…LiveActivity_途中通知_初期実用版_決定記録.md`。

## iPhone側の実装
- 今日のゴールと工程の追加・選択・完了状態
- 計画なしのタイマー開始、工程からの開始
- 当初時間のバー、5分延長の別バー、超過・残り表示
- 24時間バー上の活動範囲と現在位置／活動終了までの時間
- 中断・再開・終了、工程完了とは分離
- 任意の完成条件・後回しメモ
- Apple標準Speechフレームワークによる日本語音声文字起こし、編集後に入力反映
- 途中リマインド通知（オフ/5/10/15分ごと、初期10分）、残り5分・終了通知（通知設定・集中モード等に依存）
- Live Activity（ロック画面・Dynamic Island。Widget Extension `FocusTimerWidgets`、iOS 18以上）
- 作業画面に「今日のゴール → 今の工程」を表示
- UserDefaultsへのローカル保存。アプリ起動時に保存日が今日でなければゴールとセッションを初期化（前日のゴールの翌日繰越は未対応）

## 未実装・未検証
- Watchとの双方向同期、Watchへの独立通知や確実な振動、Watchネイティブアプリのビルド
- 自然文を解析して複数目標や工程、時間を抽出するAI入力
- 音声操作による中断・完了などの状態変更
- 音声認識の正確さ、通知の再スケジュール挙動
- Widget Extension付きIPAを無料Apple ID＋iloaderで導入できるか
- Live Activityのロック画面・Dynamic Island・Apple Watchスマートスタックでの実表示

## 検証状況
- TimerStoreの工程完了、活動範囲、日付切り替え、経過時間計算はXCTestを追加済み
- 途中通知の予約計画、Live Activityの表示内容、TimerStoreとの連携はXCTestを追加済み
- 2026-10-14 iloader v2.3.7（anisette: SideStore (.zip)）で拡張なし版の実機インストールに成功
- GitHub ActionsでXcodeGen後にiPhone Simulatorの単体テストを実行

`WatchPrototype/WatchHomeView.swift` は**独立したUI参考コード**であり、Watchへのインストール対象ではありません。Apple Watch対応完了とは見なさないでください。

## ビルド方法
1. Windowsでこのフォルダの中身をGitHubリポジトリのルートへアップロード。
2. GitHub Actions → `Build unsigned iPhone IPA` → `Run workflow`。
3. `FocusTimer-unsigned-ipa` アーティファクトをダウンロード。
4. Windowsでiloader等を使いApple Accountで署名してiPhoneにインストール。
5. iPhoneでデベロッパモードが必要になる場合あり。無料署名の期限は通常7日間。

**注意**：Xcodeがない環境で作成した未ビルドのソースです。Actionsでコンパイルエラーが出た場合、そのログをClaude Codeに渡し修正してください。XcodeGen・署名の設定は環境に応じて調整が必要です。
