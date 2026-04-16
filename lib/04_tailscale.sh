#!/usr/bin/env bash
# lib/04_tailscale.sh - Tailscale 導入・設定
# このファイルは setup.sh から source されます。単体実行不可。

# ---------------------------------------------------------------------------
# Tailscale セットアップメイン関数
# ---------------------------------------------------------------------------
function setup_tailscale() {
  step "Tailscale を設定しています..."

  # Tailscale が既に動作中なら全スキップ
  local ts_status
  ts_status=$(remote_exec "tailscale status --json 2>/dev/null | grep -o '\"BackendState\":\"[^\"]*\"'" 2>/dev/null || echo "")
  if echo "${ts_status}" | grep -q '"Running"'; then
    TAILSCALE_IP=$(remote_exec "tailscale ip -4 2>/dev/null" 2>/dev/null || echo "")
    if [ -n "${TAILSCALE_IP}" ] && echo "${TAILSCALE_IP}" | grep -qE '^100\.'; then
      success "Tailscale は既に動作中です。スキップします (IP: ${TAILSCALE_IP})"
      return 0
    fi
  fi

  _install_tailscale_on_vm
  _join_tailscale_network
  _get_tailscale_ip
  _verify_tailscale_status
  # 注意: SSH 制限は全ての remote_exec 完了後に finalize_ssh_restriction() で実行
}

# ---------------------------------------------------------------------------
# Tailscale インストール（VM 上）
# ---------------------------------------------------------------------------
function _install_tailscale_on_vm() {
  info "Tailscale をインストールしています..."

  # 既にインストール済みか確認
  if remote_exec "command -v tailscale >/dev/null 2>&1" 2>/dev/null; then
    success "Tailscale は既にインストール済みです。スキップします"
    return 0
  fi

  remote_exec "curl -fsSL https://tailscale.com/install.sh | sudo sh" || \
    error_exit "Tailscale のインストールに失敗しました。"

  success "Tailscale インストール完了"
}

# ---------------------------------------------------------------------------
# Tailscale ネットワーク参加
# ---------------------------------------------------------------------------
function _join_tailscale_network() {
  info "Tailscale ネットワークに参加しています..."

  remote_exec "sudo tailscale up --authkey='${TAILSCALE_AUTH_KEY}' --ssh" || \
    error_exit "Tailscale への接続に失敗しました。Auth Key の有効期限と権限を確認してください。"

  success "Tailscale ネットワーク参加完了"
}

# ---------------------------------------------------------------------------
# Tailscale IP アドレス取得
# ---------------------------------------------------------------------------
function _get_tailscale_ip() {
  info "Tailscale IP アドレスを取得しています..."

  local max_attempts=12
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    TAILSCALE_IP=$(remote_exec "tailscale ip -4 2>/dev/null" 2>/dev/null || echo "")
    if [ -n "${TAILSCALE_IP}" ] && echo "${TAILSCALE_IP}" | grep -qE '^100\.'; then
      success "Tailscale IP: ${TAILSCALE_IP}"
      return 0
    fi
    info "Tailscale IP 取得待機中... (${attempt}/${max_attempts})"
    sleep 5
  done

  error_exit "Tailscale IP の取得に失敗しました。"
}

# ---------------------------------------------------------------------------
# SSH を Tailscale IP のみに制限（全 remote_exec 完了後に呼ぶこと）
# ---------------------------------------------------------------------------
function finalize_ssh_restriction() {
  step "SSH アクセスを Tailscale IP に制限しています..."

  # 既に制限済みか確認
  local listen_cfg
  listen_cfg=$(remote_exec "grep -c '^ListenAddress 100\.' /etc/ssh/sshd_config 2>/dev/null" 2>/dev/null || echo "0")
  if [ "${listen_cfg}" != "0" ]; then
    success "SSH アクセス制限は既に設定済みです。スキップします"
    return 0
  fi

  local ts_ip="${TAILSCALE_IP}"
  remote_exec "
    # 既存の ListenAddress 設定をコメントアウト
    sudo sed -i 's/^ListenAddress 0\.0\.0\.0/#ListenAddress 0.0.0.0/' /etc/ssh/sshd_config
    sudo sed -i 's/^ListenAddress ::/#ListenAddress ::/' /etc/ssh/sshd_config

    # Tailscale IP で ListenAddress を追加
    if ! grep -qF \"ListenAddress ${ts_ip}\" /etc/ssh/sshd_config; then
      echo \"ListenAddress ${ts_ip}\" | sudo tee -a /etc/ssh/sshd_config > /dev/null
    fi

    # sshd 再起動 (Ubuntu 24.04 ではサービス名が 'ssh')
    sudo systemctl restart ssh
  " || error_exit "SSH 設定の変更に失敗しました。"

  success "SSH アクセス制限設定完了 (Tailscale IP: ${ts_ip} のみ許可)"
}

# ---------------------------------------------------------------------------
# Tailscale 動作確認
# ---------------------------------------------------------------------------
function _verify_tailscale_status() {
  info "Tailscale の動作状態を確認しています..."

  local max_attempts=6
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    local status
    status=$(remote_exec "tailscale status --json 2>/dev/null | grep -o '\"BackendState\":\"[^\"]*\"'" 2>/dev/null || echo "")
    if echo "${status}" | grep -q '"Running"'; then
      success "Tailscale 動作確認完了 (BackendState: Running)"
      info "Tailscale SSH 接続先: ssh ${USER}@${TAILSCALE_IP}"
      return 0
    fi
    info "Tailscale 状態確認待機中... (${attempt}/${max_attempts})"
    sleep 10
  done

  warn "Tailscale の動作状態を確認できませんでした。"
  warn "手動で確認してください: ssh ${USER}@${TAILSCALE_IP}"
  warn "設定を続行します..."
}
