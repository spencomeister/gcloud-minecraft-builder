#!/usr/bin/env bash
# lib/01_gcp.sh - VPC・ファイアウォール・VM インスタンス作成
# このファイルは setup.sh から source されます。単体実行不可。

# ---------------------------------------------------------------------------
# GCP インフラ構築メイン関数
# ---------------------------------------------------------------------------
function setup_gcp_infrastructure() {
  step "GCP インフラを構築しています..."

  check_gcloud_auth
  set_gcloud_project
  enable_compute_api
  create_vpc_network
  create_firewall_rules
  create_vm_instance
  wait_for_ssh
}

# ---------------------------------------------------------------------------
# gcloud 認証確認
# ---------------------------------------------------------------------------
function check_gcloud_auth() {
  info "gcloud 認証状態を確認しています..."
  if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | grep -q '@'; then
    error_exit "gcloud の認証が未完了です。'gcloud auth login' を実行してください。"
  fi
  success "gcloud 認証済み"
}

# ---------------------------------------------------------------------------
# プロジェクト設定
# ---------------------------------------------------------------------------
function set_gcloud_project() {
  info "GCP プロジェクトを設定しています: ${PROJECT_ID}"
  gcloud config set project "${PROJECT_ID}" --quiet || \
    error_exit "プロジェクト ID '${PROJECT_ID}' の設定に失敗しました。"
  success "プロジェクト設定完了: ${PROJECT_ID}"
}

# ---------------------------------------------------------------------------
# Compute Engine API 有効化
# ---------------------------------------------------------------------------
function enable_compute_api() {
  info "Compute Engine API を有効化しています..."
  gcloud services enable compute.googleapis.com --quiet 2>/dev/null || \
    error_exit "Compute Engine API の有効化に失敗しました。プロジェクト ID を確認してください。"
  success "Compute Engine API 有効化完了"
}

# ---------------------------------------------------------------------------
# VPC ネットワーク作成
# ---------------------------------------------------------------------------
function create_vpc_network() {
  local network_name="${SERVER_NAME}-vpc"
  info "VPC ネットワークを作成しています: ${network_name}"

  if gcloud compute networks describe "${network_name}" --quiet 2>/dev/null; then
    warn "VPC ネットワーク '${network_name}' は既に存在します。スキップします。"
    return 0
  fi

  gcloud compute networks create "${network_name}" \
    --subnet-mode=auto \
    --quiet || \
    error_exit "VPC ネットワークの作成に失敗しました。"
  success "VPC ネットワーク作成完了: ${network_name}"
}

# ---------------------------------------------------------------------------
# ファイアウォールルール作成
# ---------------------------------------------------------------------------
function create_firewall_rules() {
  local network_name="${SERVER_NAME}-vpc"
  local tailscale_cidr="100.64.0.0/10"

  info "ファイアウォールルールを作成しています..."

  # SSH ルール
  _create_fw_rule "${SERVER_NAME}-allow-ssh" \
    "tcp:22" \
    "${tailscale_cidr}" \
    "${network_name}"

  # Minecraft ルール
  _create_fw_rule "${SERVER_NAME}-allow-mc" \
    "tcp:25565" \
    "${tailscale_cidr}" \
    "${network_name}"

  # Velocity ルール（Velocity 導入時のみ）
  if [ "${VELOCITY_ENABLED:-false}" = "true" ]; then
    _create_fw_rule "${SERVER_NAME}-allow-velocity" \
      "tcp:25577" \
      "${tailscale_cidr}" \
      "${network_name}"
  fi

  # SimpleVoiceChat ルール（VoiceChat 導入時のみ）
  if [ "${VOICECHAT_ENABLED:-false}" = "true" ]; then
    _create_fw_rule "${SERVER_NAME}-allow-voicechat" \
      "udp:24454" \
      "${tailscale_cidr}" \
      "${network_name}"
  fi

  success "ファイアウォールルール作成完了"
}

function _create_fw_rule() {
  local rule_name="$1"
  local allow="$2"
  local source_ranges="$3"
  local network="$4"

  if gcloud compute firewall-rules describe "${rule_name}" --quiet 2>/dev/null; then
    warn "ファイアウォールルール '${rule_name}' は既に存在します。スキップします。"
    return 0
  fi

  gcloud compute firewall-rules create "${rule_name}" \
    --allow="${allow}" \
    --source-ranges="${source_ranges}" \
    --network="${network}" \
    --quiet || \
    error_exit "ファイアウォールルール '${rule_name}' の作成に失敗しました。"
  info "ルール作成: ${rule_name} (${allow})"
}

# ---------------------------------------------------------------------------
# VM インスタンス作成
# ---------------------------------------------------------------------------
function create_vm_instance() {
  local zone="${REGION}-a"
  info "VM インスタンスを作成しています: ${SERVER_NAME} (${zone})"

  if gcloud compute instances describe "${SERVER_NAME}" --zone="${zone}" --quiet 2>/dev/null; then
    warn "VM インスタンス '${SERVER_NAME}' は既に存在します。スキップします。"
    return 0
  fi

  gcloud compute instances create "${SERVER_NAME}" \
    --machine-type="${MACHINE_TYPE}" \
    --zone="${zone}" \
    --boot-disk-type="pd-standard" \
    --boot-disk-size="${DISK_SIZE}GB" \
    --image-family="ubuntu-2404-lts" \
    --image-project="ubuntu-os-cloud" \
    --network="${SERVER_NAME}-vpc" \
    --quiet || \
    error_exit "VM インスタンスの作成に失敗しました。GCP コンソールで詳細を確認してください。"

  success "VM インスタンス作成完了: ${SERVER_NAME}"

  # 外部 IP を取得
  VM_EXTERNAL_IP=$(gcloud compute instances describe "${SERVER_NAME}" \
    --zone="${zone}" \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)
  info "外部 IP アドレス: ${VM_EXTERNAL_IP}"
}

# ---------------------------------------------------------------------------
# SSH 接続待機
# ---------------------------------------------------------------------------
function wait_for_ssh() {
  local zone="${REGION}-a"
  local max_attempts=30
  local attempt=0

  info "VM への SSH 接続が成立するまで待機しています..."

  while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    if gcloud compute ssh "${SERVER_NAME}" \
        --zone="${zone}" \
        --command="echo ok" \
        --ssh-flag="-o ConnectTimeout=5" \
        --ssh-flag="-o StrictHostKeyChecking=no" \
        --quiet 2>/dev/null; then
      success "SSH 接続確立"
      return 0
    fi
    info "SSH 接続待機中... (${attempt}/${max_attempts}) 10秒後に再試行します"
    sleep 10
  done

  error_exit "VM への SSH 接続が 5 分でタイムアウトしました。ファイアウォール設定を確認してください。"
}

# ---------------------------------------------------------------------------
# VM 上でコマンドをリモート実行するヘルパー
# ---------------------------------------------------------------------------
function remote_exec() {
  local zone="${REGION}-a"
  gcloud compute ssh "${SERVER_NAME}" \
    --zone="${zone}" \
    --ssh-flag="-o StrictHostKeyChecking=no" \
    --quiet \
    --command="$1"
}

# ---------------------------------------------------------------------------
# VM へファイルを転送するヘルパー
# ---------------------------------------------------------------------------
function remote_copy() {
  local zone="${REGION}-a"
  gcloud compute scp \
    --zone="${zone}" \
    --ssh-flag="-o StrictHostKeyChecking=no" \
    --quiet \
    "$1" "${SERVER_NAME}:$2"
}
