# 015 ビルドしたIPAをRelease `latest` へ自動公開する

- 状態: 採用
- 日付: 2026-10-14
- 関連コミット: `05ca196`
- 関連: spec/05_技術設計.md

## 背景

SideStore（ADR-003）は iPhone の上で IPA を選んでインストールする。Actions の成果物（Artifact）はログインが必要な zip なので、iPhone から直接は扱いにくい。

## 決定

- main のビルドが成功したら、Release `latest` を作り直して IPA を添付する（`permissions: contents: write`）。
- ダウンロード先の URL を固定する: `https://github.com/fujiruki/FocusTimer/releases/latest/download/FocusTimer-unsigned.ipa`

## 理由

URL が変わらないので、iPhone の Safari でいつも同じ場所から最新版を取れる。取ったファイルは SideStore の「My Apps」→「＋」で選ぶ。PC を使わずに更新できる。

## 影響

- リポジトリが公開されていることが前提。非公開だと認証なしではダウンロードできない。
- 未署名の IPA は誰でもダウンロードできる。ただし秘密情報は含まない。
- `latest` は毎回作り直すので、過去のビルドは Release に残らない。過去のビルドは Actions の Artifact から取る。

## 追記（2026-10-15）: Install from URL 用のファイル名

- SideStore の「Install from URL」で `FocusTimer-unsigned.ipa` を指定すると、「The bundle ID “lab.akeru.focustimer” does not match the one specified by the source (“FocusTimer-unsigned”)」というエラーで失敗した。
- 原因は SideStore（`AppManager.resolveApp`）の仕組みにある。URL から入れる場合、ダウンロード前の時点では URL のファイル名を Bundle ID とみなし、IPA の中の Bundle ID と照合する。
- そこで、同じ IPA を `lab.akeru.focustimer.ipa` という名前でも添付することにした。URL から入れるときはこちらを使う。前回「URL を直接入れることはできない」としたのは誤りで、ファイル名を合わせれば入れられる。
