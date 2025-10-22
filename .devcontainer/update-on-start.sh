#!/usr/bin/env bash
set -euo pipefail

# ユーザー領域（~/.local/bin）の sui / suiup を優先解決できるよう PATH を設定
export PATH="${HOME}/.local/bin:${PATH}"

# 対象プロファイルを選択（既定: devnet）。必要に応じて環境変数 SUIUP_PROFILE で変更可能
PROFILE="${SUIUP_PROFILE:-sui@devnet}"

# suiup が未導入ならインストール（冪等）
if ! command -v suiup >/dev/null 2>&1; then
  curl -sSfL https://raw.githubusercontent.com/Mystenlabs/suiup/main/install.sh | sh || true
fi

# 選択したプロファイルの最新化を試行（存在しなければインストール）
if command -v sui >/dev/null 2>&1; then
  suiup update "${PROFILE}" -y || true
else
  suiup install "${PROFILE}" -y || true
fi

# 反映されたバージョンを表示（失敗しても起動は継続）
sui --version || true