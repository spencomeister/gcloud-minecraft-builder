#!/usr/bin/env bash
# setup.sh - Minecraft GCP サーバー自動構築スクリプト エントリーポイント
# 使用方法: bash setup.sh [--resume <phase>]
#   --resume <phase>  指定フェーズから再開
#     フェーズ: gcp, java, tailscale, minecraft, config, dns, ddns
# 実行環境: Google Cloud Shell

set -euo pipefail

# ---------------------------------------------------------------------------
# パス解決（Cloud Shell の clone 先パスに依存しない）
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"

# ---------------------------------------------------------------------------
# モジュール読み込み
# ---------------------------------------------------------------------------
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/01_gcp.sh
source "${SCRIPT_DIR}/lib/01_gcp.sh"
# shellcheck source=lib/02_java.sh
source "${SCRIPT_DIR}/lib/02_java.sh"
# shellcheck source=lib/03_minecraft.sh
source "${SCRIPT_DIR}/lib/03_minecraft.sh"
# shellcheck source=lib/04_tailscale.sh
source "${SCRIPT_DIR}/lib/04_tailscale.sh"
# shellcheck source=lib/05_cloudflare.sh
source "${SCRIPT_DIR}/lib/05_cloudflare.sh"
# shellcheck source=lib/06_ddns.sh
source "${SCRIPT_DIR}/lib/06_ddns.sh"
# shellcheck source=lib/07_config_gen.sh
source "${SCRIPT_DIR}/lib/07_config_gen.sh"

# ---------------------------------------------------------------------------
# 変数初期化
# ---------------------------------------------------------------------------
PROJECT_ID=""
SERVER_NAME=""
REGION=""
REGION_GROUP_KEY=""
MAX_PLAYERS=""
MACHINE_TYPE=""
DISK_SIZE=""
SERVER_TYPE=""
VELOCITY_ENABLED="false"
VOICECHAT_ENABLED="false"
MC_VERSION=""
JAVA_VERSION=""
DIFFICULTY="${DEFAULT_DIFFICULTY}"
GAMEMODE="${DEFAULT_GAMEMODE}"
HARDCORE="${DEFAULT_HARDCORE}"
WHITELIST="${DEFAULT_WHITELIST}"
WHITELIST_USERS=""
PVP="${DEFAULT_PVP}"
COMMAND_BLOCK="${DEFAULT_COMMAND_BLOCK}"
ALLOW_FLIGHT="${DEFAULT_ALLOW_FLIGHT}"
CF_API_TOKEN=""
CF_ZONE_ID=""
CF_DOMAIN=""
CF_SRV_HOST=""
CF_A_RECORD_ID=""
TAILSCALE_AUTH_KEY=""
VM_EXTERNAL_IP=""
TAILSCALE_IP=""
JVM_MEM=""
JVM_FLAGS=""
VELOCITY_SECRET=""

# ---------------------------------------------------------------------------
# 設定ファイルパス
# ---------------------------------------------------------------------------
CONFIG_FILE="${SCRIPT_DIR}/.last-config.env"

# ---------------------------------------------------------------------------
# クリーンアップ（スクリプト終了時に機密情報を消去）
# ---------------------------------------------------------------------------
function cleanup() {
  unset CF_API_TOKEN
  unset TAILSCALE_AUTH_KEY
  unset VELOCITY_SECRET
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 設定保存（機密情報を除く）
# ---------------------------------------------------------------------------
function save_config() {
  cat > "${CONFIG_FILE}" <<EOF
# Minecraft GCP Builder - 保存済み設定
# 生成日時: $(date '+%Y-%m-%d %H:%M:%S')
# ※ API Token / Auth Key は含まれません（セキュリティ上の理由）
PROJECT_ID="${PROJECT_ID}"
SERVER_NAME="${SERVER_NAME}"
REGION="${REGION}"
MAX_PLAYERS="${MAX_PLAYERS}"
MACHINE_TYPE="${MACHINE_TYPE}"
DISK_SIZE="${DISK_SIZE}"
SERVER_TYPE="${SERVER_TYPE}"
VELOCITY_ENABLED="${VELOCITY_ENABLED}"
VOICECHAT_ENABLED="${VOICECHAT_ENABLED}"
MC_VERSION="${MC_VERSION}"
JAVA_VERSION="${JAVA_VERSION}"
DIFFICULTY="${DIFFICULTY}"
GAMEMODE="${GAMEMODE}"
HARDCORE="${HARDCORE}"
WHITELIST="${WHITELIST}"
WHITELIST_USERS="${WHITELIST_USERS}"
PVP="${PVP}"
COMMAND_BLOCK="${COMMAND_BLOCK}"
ALLOW_FLIGHT="${ALLOW_FLIGHT}"
CF_ZONE_ID="${CF_ZONE_ID}"
CF_DOMAIN="${CF_DOMAIN}"
CF_SRV_HOST="${CF_SRV_HOST}"
CF_A_RECORD_ID="${CF_A_RECORD_ID}"
TAILSCALE_IP="${TAILSCALE_IP}"
VM_EXTERNAL_IP="${VM_EXTERNAL_IP}"
EOF
  chmod 600 "${CONFIG_FILE}"
  info "設定を ${CONFIG_FILE} に保存しました"
}

# ---------------------------------------------------------------------------
# 保存済み設定の読み込み確認
# ---------------------------------------------------------------------------
function try_load_config() {
  if [ ! -f "${CONFIG_FILE}" ]; then
    return 1
  fi

  echo ""
  info "前回の設定が見つかりました: ${CONFIG_FILE}"
  echo ""

  # 保存済み設定を一時読み込みして表示
  (
    source "${CONFIG_FILE}"
    echo "    プロジェクト ID : ${PROJECT_ID}"
    echo "    サーバー名      : ${SERVER_NAME}"
    echo "    リージョン      : ${REGION}"
    echo "    マシンタイプ    : ${MACHINE_TYPE}"
    echo "    ディスクサイズ  : ${DISK_SIZE} GB"
    echo "    サーバー種別    : ${SERVER_TYPE}"
    echo "    MC バージョン   : ${MC_VERSION}"
    echo "    ドメイン        : ${CF_DOMAIN}"
  )

  echo ""
  read -rp "  前回の設定を再利用しますか？ [Y/n]: " load_choice
  if [ "${load_choice}" = "n" ] || [ "${load_choice}" = "N" ]; then
    return 1
  fi

  # 設定ファイルを読み込み
  source "${CONFIG_FILE}"
  REGION_GROUP_KEY="${REGION_GROUP[$REGION]}"
  success "保存済み設定を読み込みました"
  echo ""
  return 0
}

# ---------------------------------------------------------------------------
# ヘッダー表示
# ---------------------------------------------------------------------------
function show_header() {
  echo ""
  echo -e "${BOLD}${CYAN}================================================${NC}"
  echo -e "${BOLD}${CYAN}  Minecraft GCP サーバー自動構築スクリプト${NC}"
  echo -e "${BOLD}${CYAN}  Version 2.0.0${NC}"
  echo -e "${BOLD}${CYAN}================================================${NC}"
  echo ""
  info "このスクリプトは対話式で GCP 上に Minecraft サーバーを構築します。"
  info "全 12 ステップで設定を入力し、最後に確認してから構築を開始します。"
  echo ""
}

# ---------------------------------------------------------------------------
# Step 1/12: GCP プロジェクト ID
# ---------------------------------------------------------------------------
function step_01_project_id() {
  echo -e "${BOLD}[Step  1/12] GCP プロジェクト設定${NC}"
  echo ""

  while true; do
    read -rp "  GCP プロジェクト ID を入力してください: " PROJECT_ID
    validate_not_empty "${PROJECT_ID}" "プロジェクト ID"
    if echo "${PROJECT_ID}" | grep -qE '^[a-z][a-z0-9\-]{5,29}$'; then
      break
    else
      warn "プロジェクト ID は英小文字・数字・ハイフンのみ、6〜30 文字で入力してください。"
    fi
  done

  success "プロジェクト ID: ${PROJECT_ID}"
  echo ""
}

# ---------------------------------------------------------------------------
# Step 2/12: サーバー名
# ---------------------------------------------------------------------------
function step_02_server_name() {
  echo -e "${BOLD}[Step  2/12] サーバー名設定${NC}"
  echo ""
  echo "  ※ VM 名・ディレクトリ名に使用します"
  echo "  ※ 英小文字・数字・ハイフンのみ、先頭は英字（例: mymc-server）"
  echo ""

  while true; do
    read -rp "  サーバー名を入力してください: " SERVER_NAME
    validate_not_empty "${SERVER_NAME}" "サーバー名"
    if echo "${SERVER_NAME}" | grep -qE '^[a-z][a-z0-9\-]{0,31}$'; then
      break
    else
      warn "サーバー名は英小文字・数字・ハイフンのみ、1〜32 文字、先頭はアルファベットで入力してください。"
    fi
  done

  success "サーバー名: ${SERVER_NAME}"
  echo ""
}

# ---------------------------------------------------------------------------
# Step 3/12: リージョン選択
# ---------------------------------------------------------------------------
function step_03_region() {
  echo -e "${BOLD}[Step  3/12] リージョン選択${NC}"
  echo ""
  echo "  1) us-west1        (Oregon      / 無料枠対象)"
  echo "  2) us-central1     (Iowa        / 無料枠対象)"
  echo "  3) us-east1        (S.Carolina  / 無料枠対象)"
  echo "  4) asia-northeast1 (東京)"
  echo "  5) asia-northeast2 (大阪)"
  echo ""

  while true; do
    read -rp "  選択 [1-5]: " region_choice
    case "${region_choice}" in
      1) REGION="us-west1";        break ;;
      2) REGION="us-central1";     break ;;
      3) REGION="us-east1";        break ;;
      4) REGION="asia-northeast1"; break ;;
      5) REGION="asia-northeast2"; break ;;
      *) warn "1〜5 の数字を入力してください。" ;;
    esac
  done

  REGION_GROUP_KEY="${REGION_GROUP[$REGION]}"
  success "リージョン: ${REGION} (${REGION_LABEL[$REGION]})"
  echo ""
}

# ---------------------------------------------------------------------------
# Step 4/12: プレイヤー数・マシンタイプ
# ---------------------------------------------------------------------------
function step_04_players_and_machine() {
  echo -e "${BOLD}[Step  4/12] プレイヤー数・マシンタイプ${NC}"
  echo ""

  while true; do
    read -rp "  想定同時接続プレイヤー数を入力してください: " MAX_PLAYERS
    if echo "${MAX_PLAYERS}" | grep -qE '^[0-9]+$' && [ "${MAX_PLAYERS}" -ge 1 ]; then
      break
    else
      warn "プレイヤー数は 1 以上の整数で入力してください。"
    fi
  done

  # 推奨マシンタイプを算出
  local recommended
  recommended=$(get_recommended_machine "${MAX_PLAYERS}")

  # 無料枠リージョンかどうか確認
  local is_free_region="false"
  for free_region in "${FREE_TIER_REGIONS[@]}"; do
    if [ "${REGION}" = "${free_region}" ]; then
      is_free_region="true"
      break
    fi
  done

  # 料金テーブル表示
  show_price_table "${REGION_GROUP_KEY}" "${recommended}" "${REGION_LABEL[$REGION]}" "${is_free_region}"

  # 無料枠ガイダンス
  if [ "${is_free_region}" = "true" ] && [ "${recommended}" = "e2-micro" ]; then
    info "e2-micro は米国リージョンで月 730 時間分が無料枠対象です（ディスク・ネットワーク料金は別途）"
  elif [ "${is_free_region}" = "true" ] && [ "${MAX_PLAYERS}" -ge 4 ]; then
    warn "4 人以上では e2-micro（無料枠）は推奨されません。推奨マシン: ${recommended}"
  fi
  echo ""

  echo -e "  ${GREEN}推奨: ${recommended}${NC}"
  read -rp "  このマシンタイプで進めますか？ [y/n]: " use_recommended

  if [ "${use_recommended}" = "y" ] || [ "${use_recommended}" = "Y" ]; then
    MACHINE_TYPE="${recommended}"
  else
    while true; do
      read -rp "  マシンタイプを手動入力してください: " MACHINE_TYPE
      validate_not_empty "${MACHINE_TYPE}" "マシンタイプ"
      break
    done
  fi

  success "マシンタイプ: ${MACHINE_TYPE}"
  echo ""
}

# ---------------------------------------------------------------------------
# Step 5/12: ディスクサイズ
# ---------------------------------------------------------------------------
function step_05_disk_size() {
  echo -e "${BOLD}[Step  5/12] ディスクサイズ${NC}"
  echo ""
  echo "  推奨: 50GB 以上（ワールドデータは増加します）"
  echo ""

  while true; do
    read -rp "  ディスクサイズを入力してください (GB): " DISK_SIZE
    if echo "${DISK_SIZE}" | grep -qE '^[0-9]+$' && [ "${DISK_SIZE}" -ge 10 ]; then
      break
    else
      warn "ディスクサイズは 10 以上の整数で入力してください。"
    fi
  done

  if [ "${DISK_SIZE}" -lt 30 ]; then
    warn "ディスクサイズが 30GB 未満です。ワールドデータが増加するとディスク不足になる可能性があります。"
  fi

  success "ディスクサイズ: ${DISK_SIZE}GB"
  echo ""
}

# ---------------------------------------------------------------------------
# Step 6/12: Minecraft サーバー種別
# ---------------------------------------------------------------------------
function step_06_server_type() {
  echo -e "${BOLD}[Step  6/12] Minecraft サーバー種別${NC}"
  echo ""
  echo "  1) Vanilla    (公式サーバー)"
  echo "  2) FabricMC   (MOD 軽量系)"
  echo "  3) SpigotMC   (プラグイン系 / BuildTools 自動ビルド)"
  echo "  4) PaperMC    (高性能プラグイン系)"
  echo ""

  while true; do
    read -rp "  選択 [1-4]: " type_choice
    case "${type_choice}" in
      1) SERVER_TYPE="vanilla"; break ;;
      2) SERVER_TYPE="fabric";  break ;;
      3) SERVER_TYPE="spigot";  break ;;
      4) SERVER_TYPE="paper";   break ;;
      *) warn "1〜4 の数字を入力してください。" ;;
    esac
  done

  success "サーバー種別: ${SERVER_TYPE}"

  # PaperMC 選択時の追加質問
  if [ "${SERVER_TYPE}" = "paper" ]; then
    echo ""
    read -rp "  Velocity プロキシを導入しますか？ [y/n]: " velocity_choice
    if [ "${velocity_choice}" = "y" ] || [ "${velocity_choice}" = "Y" ]; then
      VELOCITY_ENABLED="true"
      success "Velocity: 導入あり"

      read -rp "  SimpleVoiceChat プラグインも導入しますか？ [y/n]: " voicechat_choice
      if [ "${voicechat_choice}" = "y" ] || [ "${voicechat_choice}" = "Y" ]; then
        VOICECHAT_ENABLED="true"
        success "SimpleVoiceChat: 導入あり"
      else
        VOICECHAT_ENABLED="false"
        info "SimpleVoiceChat: スキップ"
      fi
    else
      VELOCITY_ENABLED="false"
      info "Velocity: スキップ"
    fi
  fi

  echo ""
}

# ---------------------------------------------------------------------------
# Step 7/12: Minecraft バージョン
# ---------------------------------------------------------------------------
function step_07_mc_version() {
  echo -e "${BOLD}[Step  7/12] Minecraft バージョン${NC}"
  echo ""

  while true; do
    read -rp "  Minecraft バージョンを入力してください (例: 1.21.4, 26.1.2): " MC_VERSION
    if echo "${MC_VERSION}" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
      break
    else
      warn "バージョンは 'X.Y' または 'X.Y.Z' 形式で入力してください（例: 1.21.4）"
    fi
  done

  JAVA_VERSION=$(select_java_version "${MC_VERSION}")
  success "Minecraft バージョン: ${MC_VERSION}"
  info "対応 Java: OpenJDK ${JAVA_VERSION} を自動選択します"
  echo ""
}

# ---------------------------------------------------------------------------
# Step 8/12: ゲーム基本設定
# ---------------------------------------------------------------------------
function step_08_game_settings() {
  echo -e "${BOLD}[Step  8/12] ゲーム基本設定${NC}"
  echo ""

  # 難易度
  echo "  難易度を選択してください:"
  echo "    1) peaceful  (モンスターなし)"
  echo "    2) easy      (難易度: 簡単)"
  echo "    3) normal    (難易度: 普通) ← デフォルト"
  echo "    4) hard      (難易度: 難しい)"
  echo ""

  while true; do
    read -rp "  選択 [1-4] (Enter でデフォルト): " difficulty_choice
    case "${difficulty_choice}" in
      "")  DIFFICULTY="normal";   break ;;
      1)   DIFFICULTY="peaceful"; break ;;
      2)   DIFFICULTY="easy";     break ;;
      3)   DIFFICULTY="normal";   break ;;
      4)   DIFFICULTY="hard";     break ;;
      *)   warn "1〜4 の数字を入力してください。" ;;
    esac
  done

  success "難易度: ${DIFFICULTY}"
  echo ""

  # ゲームモード
  echo "  デフォルトゲームモードを選択してください:"
  echo "    1) survival   (サバイバル) ← デフォルト"
  echo "    2) creative   (クリエイティブ)"
  echo "    3) adventure  (アドベンチャー)"
  echo "    4) spectator  (スペクテイター)"
  echo ""

  while true; do
    read -rp "  選択 [1-4] (Enter でデフォルト): " gamemode_choice
    case "${gamemode_choice}" in
      "")  GAMEMODE="survival";   break ;;
      1)   GAMEMODE="survival";   break ;;
      2)   GAMEMODE="creative";   break ;;
      3)   GAMEMODE="adventure";  break ;;
      4)   GAMEMODE="spectator";  break ;;
      *)   warn "1〜4 の数字を入力してください。" ;;
    esac
  done

  success "ゲームモード: ${GAMEMODE}"
  echo ""

  # ハードコアモード
  echo "  ハードコアモードを有効にしますか？"
  echo "  ※ 有効にすると難易度が hard に固定されます"
  echo ""

  read -rp "  ハードコアモード [y/N] (デフォルト: n): " hardcore_choice
  if [ "${hardcore_choice}" = "y" ] || [ "${hardcore_choice}" = "Y" ]; then
    HARDCORE="true"
    DIFFICULTY="hard"
    success "ハードコアモード: 有効 (難易度を hard に固定しました)"
  else
    HARDCORE="false"
    info "ハードコアモード: 無効"
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# Step 9/12: セキュリティ設定
# ---------------------------------------------------------------------------
function step_09_security_settings() {
  echo -e "${BOLD}[Step  9/12] セキュリティ設定${NC}"
  echo ""

  # ホワイトリスト
  echo "  ホワイトリストを強制しますか？"
  echo "  ※ 有効にすると whitelist.json に登録されたプレイヤーのみ接続可能です"
  echo ""
  read -rp "  ホワイトリスト [Y/n] (デフォルト: y): " whitelist_choice
  if [ "${whitelist_choice}" = "n" ] || [ "${whitelist_choice}" = "N" ]; then
    WHITELIST="false"
    info "ホワイトリスト: 無効"
  else
    WHITELIST="true"
    success "ホワイトリスト: 有効"

    echo ""
    echo "  初期ホワイトリストのユーザー名を入力してください"
    echo "  (複数の場合はカンマ区切り、後から whitelist.json を直接編集することも可能)"
    echo "  例: Steve,Alex,Notch"
    echo ""
    read -rp "  入力 (空欄でスキップ): " WHITELIST_USERS

    if [ -n "${WHITELIST_USERS}" ]; then
      info "初期 WL ユーザー: ${WHITELIST_USERS}"
    else
      info "初期 WL ユーザー: なし（後から whitelist.json を編集してください）"
    fi
  fi
  echo ""

  # PvP
  read -rp "  PvP を許可しますか？ [y/N] (デフォルト: n): " pvp_choice
  if [ "${pvp_choice}" = "y" ] || [ "${pvp_choice}" = "Y" ]; then
    PVP="true"
    info "PvP: 有効"
  else
    PVP="false"
    info "PvP: 無効"
  fi
  echo ""

  # コマンドブロック
  read -rp "  コマンドブロックを許可しますか？ [y/N] (デフォルト: n): " cmdblock_choice
  if [ "${cmdblock_choice}" = "y" ] || [ "${cmdblock_choice}" = "Y" ]; then
    COMMAND_BLOCK="true"
    info "コマンドブロック: 有効"
  else
    COMMAND_BLOCK="false"
    info "コマンドブロック: 無効"
  fi
  echo ""

  # フライト
  echo "  フライト(飛行)を許可しますか？"
  echo "  ※ サバイバルモードでのフライトを許可します (Creative は常に可能)"
  echo ""
  read -rp "  フライト許可 [y/N] (デフォルト: n): " flight_choice
  if [ "${flight_choice}" = "y" ] || [ "${flight_choice}" = "Y" ]; then
    ALLOW_FLIGHT="true"
    info "フライト許可: 有効"
  else
    ALLOW_FLIGHT="false"
    info "フライト許可: 無効"
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# Step 10/12: Cloudflare 設定
# ---------------------------------------------------------------------------
function step_10_cloudflare() {
  echo -e "${BOLD}[Step 10/12] Cloudflare 設定${NC}"
  echo ""

  while true; do
    read -rsp "  API Token (入力は非表示): " CF_API_TOKEN
    echo ""
    validate_not_empty "${CF_API_TOKEN}" "Cloudflare API Token"

    read -rp "  Zone ID   : " CF_ZONE_ID
    validate_not_empty "${CF_ZONE_ID}" "Zone ID"

    read -rp "  ドメイン  (例: mc.example.com): " CF_DOMAIN
    validate_not_empty "${CF_DOMAIN}" "ドメイン"

    read -rp "  SRV ホスト (例: _minecraft._tcp.example.com): " CF_SRV_HOST
    validate_not_empty "${CF_SRV_HOST}" "SRV ホスト"

    # API 疎通確認
    info "Cloudflare API の疎通を確認しています..."
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}" \
      2>/dev/null || echo "000")

    if [ "${response}" = "200" ]; then
      success "Cloudflare API 疎通確認完了"
      break
    else
      warn "Cloudflare API の認証に失敗しました (HTTP ${response})。API Token と Zone ID を確認してください。"
      echo ""
    fi
  done
  echo ""
}

# ---------------------------------------------------------------------------
# Step 11/12: Tailscale Auth Key
# ---------------------------------------------------------------------------
function step_11_tailscale() {
  echo -e "${BOLD}[Step 11/12] Tailscale 設定${NC}"
  echo ""

  while true; do
    read -rsp "  Tailscale Auth Key (入力は非表示): " TAILSCALE_AUTH_KEY
    echo ""
    if [ -n "${TAILSCALE_AUTH_KEY}" ]; then
      break
    else
      warn "Tailscale Auth Key は空欄にできません。"
    fi
  done

  success "Tailscale Auth Key: 入力済み"
  echo ""
}

# ---------------------------------------------------------------------------
# Step 12/12: 設定サマリー確認
# ---------------------------------------------------------------------------
function step_12_summary() {
  local velocity_display="なし"
  local voicechat_display="なし"
  local whitelist_display="無効"
  local whitelist_users_display="${WHITELIST_USERS:-なし}"
  local pvp_display="無効"
  local cmdblock_display="無効"
  local flight_display="無効"
  local hardcore_display="なし"

  [ "${VELOCITY_ENABLED}" = "true" ]  && velocity_display="あり"
  [ "${VOICECHAT_ENABLED}" = "true" ] && voicechat_display="あり"
  [ "${WHITELIST}" = "true" ]         && whitelist_display="有効"
  [ "${PVP}" = "true" ]               && pvp_display="有効"
  [ "${COMMAND_BLOCK}" = "true" ]     && cmdblock_display="有効"
  [ "${ALLOW_FLIGHT}" = "true" ]      && flight_display="有効"
  [ "${HARDCORE}" = "true" ]          && hardcore_display="あり"

  echo ""
  echo -e "${BOLD}================================================${NC}"
  echo -e "${BOLD}  設定サマリー確認${NC}"
  echo -e "${BOLD}================================================${NC}"
  echo ""
  echo "  [インフラ]"
  printf "  %-20s: %s\n" "プロジェクト ID"  "${PROJECT_ID}"
  printf "  %-20s: %s\n" "サーバー名"       "${SERVER_NAME}"
  printf "  %-20s: %s\n" "リージョン"       "${REGION} (${REGION_LABEL[$REGION]})"
  printf "  %-20s: %s\n" "マシンタイプ"     "${MACHINE_TYPE}"
  printf "  %-20s: %s GB\n" "ディスクサイズ" "${DISK_SIZE}"
  echo ""
  echo "  [Minecraft]"
  printf "  %-20s: %s\n" "サーバー種別"     "${SERVER_TYPE}"
  printf "  %-20s: %s\n" "Velocity"         "${velocity_display}"
  printf "  %-20s: %s\n" "SimpleVoiceChat"  "${voicechat_display}"
  printf "  %-20s: %s\n" "MC バージョン"    "${MC_VERSION}"
  printf "  %-20s: OpenJDK %s\n" "Java"     "${JAVA_VERSION}"
  echo ""
  echo "  [ゲーム設定]"
  printf "  %-20s: %s\n" "難易度"           "${DIFFICULTY}"
  printf "  %-20s: %s\n" "ゲームモード"     "${GAMEMODE}"
  printf "  %-20s: %s\n" "ハードコア"       "${hardcore_display}"
  printf "  %-20s: %s\n" "ホワイトリスト"   "${whitelist_display}"
  printf "  %-20s: %s\n" "初期 WL ユーザー" "${whitelist_users_display}"
  printf "  %-20s: %s\n" "PvP"              "${pvp_display}"
  printf "  %-20s: %s\n" "コマンドブロック" "${cmdblock_display}"
  printf "  %-20s: %s\n" "フライト許可"     "${flight_display}"
  echo ""
  echo "  [DNS / アクセス]"
  printf "  %-20s: %s\n" "ドメイン"         "${CF_DOMAIN}"
  printf "  %-20s: %s\n" "SRV"              "${CF_SRV_HOST}"
  printf "  %-20s: %s\n" "DDNS 更新"        "起動時 + 5 分毎 (Cron)"
  printf "  %-20s: %s\n" "EULA"             "自動同意 (true)"
  echo ""
  echo -e "${BOLD}================================================${NC}"
  echo ""

  read -rp "この設定で実行しますか？ [y/n]: " confirm
  if [ "${confirm}" != "y" ] && [ "${confirm}" != "Y" ]; then
    echo ""
    info "セットアップを中断しました。"
    info "再度実行するには: bash ${BASH_SOURCE[0]}"
    exit 0
  fi

  echo ""
  success "セットアップを開始します..."
  echo ""
}

# ---------------------------------------------------------------------------
# 完了メッセージ表示
# ---------------------------------------------------------------------------
function show_completion_message() {
  echo ""
  echo -e "${BOLD}${GREEN}================================================${NC}"
  echo -e "${BOLD}${GREEN}  Minecraft サーバーのセットアップが完了しました！${NC}"
  echo -e "${BOLD}${GREEN}================================================${NC}"
  echo ""
  echo "  [接続情報]"
  printf "  %-25s: %s\n" "Tailscale IP (SSH用)"       "${TAILSCALE_IP}"
  printf "  %-25s: %s\n" "Minecraft 接続先"            "${CF_DOMAIN}"
  printf "  %-25s: %s\n" "外部 IP (DDNS対象)"          "${VM_EXTERNAL_IP}"
  echo ""
  echo "  [SSH 接続方法]"
  echo "    ssh ${USER}@${TAILSCALE_IP}"
  echo ""
  echo "  [ログ確認]"
  echo "    journalctl -u minecraft-${SERVER_NAME} -f"

  if [ "${VELOCITY_ENABLED}" = "true" ]; then
    echo "    journalctl -u velocity -f"
  fi

  echo "    tail -f /var/log/minecraft-ddns.log"
  echo ""

  if [ "${WHITELIST}" = "true" ]; then
    echo "  [ホワイトリスト管理]"
    echo "    ホワイトリストにプレイヤーを追加するには:"
    echo "    ssh ${USER}@${TAILSCALE_IP}"
    echo "    sudo -u minecraft nano /opt/minecraft/${SERVER_NAME}/whitelist.json"
    echo "    ゲーム内: /whitelist reload"
    echo ""
  fi

  echo -e "${BOLD}${CYAN}  Enjoy Minecraft! 🎮${NC}"
  echo ""
}

# ---------------------------------------------------------------------------
# メイン処理
# ---------------------------------------------------------------------------

# ビルドフェーズ順序定義
BUILD_PHASES=("gcp" "java" "tailscale" "dns" "ddns" "config" "minecraft")

function show_resume_help() {
  echo ""
  echo "  使用方法: bash setup.sh [--resume <phase>]"
  echo ""
  echo "  --resume <phase>  指定フェーズから構築を再開"
  echo "  ※ 完了済みフェーズは自動スキップされます"
  echo ""
  echo "  フェーズ一覧 (実行順):"
  echo "    gcp        GCP インフラ構築 (VPC / FW / VM)"
  echo "    java       Java インストール"
  echo "    tailscale  Tailscale セットアップ            [要: Tailscale Auth Key]"
  echo "    dns        Cloudflare DNS 設定              [要: Cloudflare API Token]"
  echo "    ddns       DDNS セットアップ                  [要: Cloudflare API Token]"
  echo "    config     設定ファイル生成"
  echo "    minecraft  Minecraft サーバーインストール"
  echo ""
}

function should_run_phase() {
  local phase="$1"
  local resume_from="${RESUME_PHASE:-}"

  # --resume 指定なし → 全フェーズ実行
  if [ -z "${resume_from}" ]; then
    return 0
  fi

  # 指定フェーズ以降か判定
  local found_resume=false
  for p in "${BUILD_PHASES[@]}"; do
    if [ "${p}" = "${resume_from}" ]; then
      found_resume=true
    fi
    if [ "${found_resume}" = true ] && [ "${p}" = "${phase}" ]; then
      return 0
    fi
  done
  return 1
}

function main() {
  # 引数パース
  RESUME_PHASE=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --resume)
        shift
        RESUME_PHASE="${1:-}"
        if [ -z "${RESUME_PHASE}" ]; then
          show_resume_help
          error_exit "--resume にはフェーズ名を指定してください。"
        fi
        # フェーズ名バリデーション
        local valid=false
        for p in "${BUILD_PHASES[@]}"; do
          [ "${p}" = "${RESUME_PHASE}" ] && valid=true
        done
        if [ "${valid}" = false ]; then
          show_resume_help
          error_exit "不明なフェーズ: ${RESUME_PHASE}"
        fi
        shift
        ;;
      --help|-h)
        show_resume_help
        exit 0
        ;;
      *)
        shift
        ;;
    esac
  done

  show_header

  if [ -n "${RESUME_PHASE}" ]; then
    # --resume 指定時: 保存済み設定を必須で読み込み
    if [ ! -f "${CONFIG_FILE}" ]; then
      error_exit "保存済み設定が見つかりません。先に通常実行で設定を完了させてください。"
    fi
    source "${CONFIG_FILE}"
    REGION_GROUP_KEY="${REGION_GROUP[$REGION]}"
    info "保存済み設定を読み込みました"
    info "フェーズ '${RESUME_PHASE}' から再開します"
    echo ""

    # 必要な機密情報のみ再入力
    # tailscale フェーズが実行対象 → Tailscale Auth Key が必要
    if should_run_phase "tailscale"; then
      step_11_tailscale
    else
      info "Tailscale は完了済みです。Auth Key の入力をスキップします"
    fi

    # dns または ddns フェーズが実行対象 → Cloudflare API Token が必要
    if should_run_phase "dns" || should_run_phase "ddns"; then
      step_10_cloudflare
    else
      info "Cloudflare DNS は完了済みです。API Token の入力をスキップします"
    fi

    # VM の外部 IP を取得（既存 VM から）
    if [ -z "${VM_EXTERNAL_IP:-}" ]; then
      VM_EXTERNAL_IP=$(gcloud compute instances describe "${SERVER_NAME}" \
        --zone="${REGION}-a" \
        --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "")
    fi

    # Tailscale IP を復元（保存済み設定になければ VM から取得）
    if [ -z "${TAILSCALE_IP:-}" ]; then
      info "Tailscale IP を VM から取得しています..."
      TAILSCALE_IP=$(gcloud compute ssh "${SERVER_NAME}" \
        --zone="${REGION}-a" \
        --tunnel-through-iap \
        --ssh-flag="-o ConnectTimeout=10" \
        --ssh-flag="-o StrictHostKeyChecking=no" \
        --quiet \
        --command="tailscale ip -4 2>/dev/null" 2>/dev/null || echo "")
      if [ -n "${TAILSCALE_IP}" ]; then
        info "Tailscale IP: ${TAILSCALE_IP}"
      fi
    fi

    # CF_A_RECORD_ID を復元（保存済み設定になければ Cloudflare API から取得）
    if [ -z "${CF_A_RECORD_ID:-}" ] && [ -n "${CF_API_TOKEN:-}" ]; then
      info "Cloudflare A レコード ID を取得しています..."
      CF_A_RECORD_ID=$(curl -s \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${CF_DOMAIN}" | \
        python3 -c "
import sys, json
data = json.load(sys.stdin)
records = data.get('result', [])
print(records[0]['id']) if records else print('')
" 2>/dev/null || echo "")
      if [ -n "${CF_A_RECORD_ID}" ]; then
        info "A レコード ID: ${CF_A_RECORD_ID}"
      fi
    fi
  else
    # 通常実行
    if try_load_config; then
      step_10_cloudflare
      step_11_tailscale
    else
      step_01_project_id
      step_02_server_name
      step_03_region
      step_04_players_and_machine
      step_05_disk_size
      step_06_server_type
      step_07_mc_version
      step_08_game_settings
      step_09_security_settings
      step_10_cloudflare
      step_11_tailscale
    fi

    step_12_summary
    save_config
  fi

  # --resume 時: remote_exec が必要なフェーズがある場合、IAP SSH の疎通を事前確認
  if [ -n "${RESUME_PHASE}" ] && [ "${RESUME_PHASE}" != "gcp" ]; then
    ensure_iap_ssh
  fi

  # ビルドフェーズ実行
  should_run_phase "gcp"       && setup_gcp_infrastructure
  should_run_phase "java"      && install_java_on_vm
  should_run_phase "tailscale" && setup_tailscale
  should_run_phase "dns"       && setup_cloudflare_dns
  should_run_phase "ddns"      && setup_ddns
  should_run_phase "config"    && generate_config_files
  should_run_phase "minecraft" && install_minecraft_server

  # SSH 制限は全ての remote_exec が完了した後に実行
  # （これ以降 IAP 経由の SSH は不可になる）
  should_run_phase "tailscale" && finalize_ssh_restriction

  # ビルド完了後に設定を保存（ランタイム値を含む）
  save_config

  show_completion_message
}

main "$@"
