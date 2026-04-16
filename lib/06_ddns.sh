#!/usr/bin/env bash
# lib/06_ddns.sh - DDNS 更新スクリプト生成・Cron 登録
# このファイルは setup.sh から source されます。単体実行不可。

# ---------------------------------------------------------------------------
# DDNS セットアップメイン関数
# ---------------------------------------------------------------------------
function setup_ddns() {
  step "DDNS 更新スクリプトを設定しています..."

  _generate_ddns_script
  _setup_ddns_cron
  _run_ddns_initial

  success "DDNS 設定完了"
}

# ---------------------------------------------------------------------------
# DDNS 更新スクリプト生成・配置
# ---------------------------------------------------------------------------
function _generate_ddns_script() {
  info "DDNS 更新スクリプトを生成しています..."

  sed \
    -e "s|{{CF_API_TOKEN}}|${CF_API_TOKEN}|g" \
    -e "s|{{CF_ZONE_ID}}|${CF_ZONE_ID}|g" \
    -e "s|{{CF_RECORD_ID}}|${CF_A_RECORD_ID}|g" \
    -e "s|{{CF_DOMAIN}}|${CF_DOMAIN}|g" \
    "${TEMPLATE_DIR}/ddns-update.sh.tmpl" > /tmp/ddns-update.sh

  remote_copy "/tmp/ddns-update.sh" "/tmp/ddns-update.sh"
  remote_exec "sudo mv /tmp/ddns-update.sh /opt/minecraft/ddns-update.sh && \
    sudo chown minecraft:minecraft /opt/minecraft/ddns-update.sh && \
    sudo chmod 700 /opt/minecraft/ddns-update.sh"

  rm -f /tmp/ddns-update.sh
  success "DDNS 更新スクリプト配置完了: /opt/minecraft/ddns-update.sh"
}

# ---------------------------------------------------------------------------
# Cron 設定
# ---------------------------------------------------------------------------
function _setup_ddns_cron() {
  info "Cron を設定しています (5 分ごとに DDNS 更新)..."

  remote_exec "echo '*/5 * * * * minecraft /opt/minecraft/ddns-update.sh >> /var/log/minecraft-ddns.log 2>&1' | \
    sudo tee /etc/cron.d/minecraft-ddns > /dev/null && \
    sudo chmod 644 /etc/cron.d/minecraft-ddns"

  success "Cron 設定完了"
}

# ---------------------------------------------------------------------------
# DDNS 即時実行
# ---------------------------------------------------------------------------
function _run_ddns_initial() {
  info "DDNS 更新スクリプトを即時実行しています..."

  remote_exec "sudo -u minecraft /opt/minecraft/ddns-update.sh" || \
    warn "DDNS の初回実行に失敗しました。ネットワーク設定を確認してください。"
}
