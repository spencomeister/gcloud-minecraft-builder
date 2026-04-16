#!/usr/bin/env bash
# lib/common.sh - 共通関数・定数（色・ログ・バリデーション）
# このファイルは setup.sh から source されます。単体実行不可。

# ---------------------------------------------------------------------------
# ANSI カラーコード
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# ログ関数
# ---------------------------------------------------------------------------
function info()       { echo -e "${CYAN}[INFO]${NC}    $1"; }
function success()    { echo -e "${GREEN}[OK]${NC}      $1"; }
function warn()       { echo -e "${YELLOW}[WARN]${NC}    $1"; }
function step()       { echo -e "${BOLD}${BLUE}[STEP]${NC}    $1"; }
function error_exit() { echo -e "${RED}[ERROR]${NC}   $1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# バリデーション関数
# ---------------------------------------------------------------------------
function validate_not_empty() {
  [ -n "$1" ] || error_exit "$2 は空欄にできません。"
}

function validate_regex() {
  echo "$1" | grep -qE "$2" || error_exit "$3"
}

function validate_integer_min() {
  validate_regex "$1" '^[0-9]+$' "$2 は整数で入力してください。"
  [ "$1" -ge "$3" ] || error_exit "$2 は $3 以上で入力してください。"
}

function validate_range() {
  [ "$1" -ge "$2" ] && [ "$1" -le "$3" ] || \
    error_exit "$4 は $2〜$3 の範囲で入力してください。"
}

# ---------------------------------------------------------------------------
# 料金定数
# ---------------------------------------------------------------------------
declare -A HOURLY_PRICE
HOURLY_PRICE["us:e2-micro"]="0.0084";      HOURLY_PRICE["jp:e2-micro"]="0.0150"
HOURLY_PRICE["us:e2-small"]="0.0168";      HOURLY_PRICE["jp:e2-small"]="0.0299"
HOURLY_PRICE["us:e2-medium"]="0.0335";     HOURLY_PRICE["jp:e2-medium"]="0.0598"
HOURLY_PRICE["us:e2-standard-2"]="0.0670"; HOURLY_PRICE["jp:e2-standard-2"]="0.0957"
HOURLY_PRICE["us:e2-standard-4"]="0.1340"; HOURLY_PRICE["jp:e2-standard-4"]="0.1914"

declare -A MACHINE_VCPU
MACHINE_VCPU["e2-micro"]="2 (共有)"
MACHINE_VCPU["e2-small"]="2 (共有)"
MACHINE_VCPU["e2-medium"]="2 (共有)"
MACHINE_VCPU["e2-standard-2"]="2"
MACHINE_VCPU["e2-standard-4"]="4"

declare -A MACHINE_RAM
MACHINE_RAM["e2-micro"]="1 GB"
MACHINE_RAM["e2-small"]="2 GB"
MACHINE_RAM["e2-medium"]="4 GB"
MACHINE_RAM["e2-standard-2"]="8 GB"
MACHINE_RAM["e2-standard-4"]="16 GB"

MACHINE_TYPES=("e2-micro" "e2-small" "e2-medium" "e2-standard-2" "e2-standard-4")

declare -A DISK_PRICE_PER_GB
DISK_PRICE_PER_GB["us"]="0.040"
DISK_PRICE_PER_GB["jp"]="0.052"

JPY_RATE=150  # 参考値: 1 USD = 150 JPY（料金試算用、実際の為替レートとは異なる場合があります）
HOURS_PER_DAY=24
HOURS_PER_MONTH=730

# ---------------------------------------------------------------------------
# リージョン定義
# ---------------------------------------------------------------------------
declare -A REGION_LABEL
REGION_LABEL["us-west1"]="Oregon / 無料枠対象"
REGION_LABEL["us-central1"]="Iowa / 無料枠対象"
REGION_LABEL["us-east1"]="S.Carolina / 無料枠対象"
REGION_LABEL["asia-northeast1"]="東京"
REGION_LABEL["asia-northeast2"]="大阪"

declare -A REGION_GROUP
REGION_GROUP["us-west1"]="us"
REGION_GROUP["us-central1"]="us"
REGION_GROUP["us-east1"]="us"
REGION_GROUP["asia-northeast1"]="jp"
REGION_GROUP["asia-northeast2"]="jp"

FREE_TIER_REGIONS=("us-west1" "us-central1" "us-east1")
FREE_TIER_MACHINE="e2-micro"

REGION_LIST=("us-west1" "us-central1" "us-east1" "asia-northeast1" "asia-northeast2")

# ---------------------------------------------------------------------------
# ゲーム設定のデフォルト値
# ---------------------------------------------------------------------------
DEFAULT_DIFFICULTY="normal"
DEFAULT_GAMEMODE="survival"
DEFAULT_HARDCORE="false"
DEFAULT_WHITELIST="true"
DEFAULT_PVP="false"
DEFAULT_COMMAND_BLOCK="false"
DEFAULT_ALLOW_FLIGHT="false"

# ---------------------------------------------------------------------------
# Minecraft API エンドポイント
# ---------------------------------------------------------------------------
MOJANG_VERSION_MANIFEST="https://launchermeta.mojang.com/mc/game/version_manifest.json"
FABRIC_INSTALLER_API="https://meta.fabricmc.net/v2/versions/installer"
SPIGOT_BUILD_TOOLS_URL="https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar"
PAPER_API_BASE="https://api.papermc.io/v2/projects"
VOICECHAT_RELEASES_API="https://api.github.com/repos/henkelmax/simple-voice-chat/releases/latest"
MOJANG_UUID_API="https://api.mojang.com/users/profiles/minecraft"

# ---------------------------------------------------------------------------
# 推奨マシンタイプ自動判定
# ---------------------------------------------------------------------------
function get_recommended_machine() {
  local players=$1
  if   [ "$players" -le 3  ]; then echo "e2-micro"
  elif [ "$players" -le 8  ]; then echo "e2-small"
  elif [ "$players" -le 20 ]; then echo "e2-medium"
  elif [ "$players" -le 50 ]; then echo "e2-standard-2"
  else                              echo "e2-standard-4"
  fi
}

# ---------------------------------------------------------------------------
# 料金テーブル表示
# ---------------------------------------------------------------------------
function show_price_table() {
  local region_group=$1
  local recommended=$2
  local region_label=$3
  local is_free_region=$4

  echo ""
  printf "  ┌──────────────────────────────────────────────────────────────┐\n"
  printf "  │  マシンタイプ推奨テーブル (%s)%s│\n" \
    "$region_label" \
    "$(printf '%*s' $((44 - ${#region_label})) '')"
  printf "  ├───────────────┬────────────┬────────┬────────┬──────────────┤\n"
  printf "  │  マシン       │ vCPU / RAM │ \$/時間 │  \$/日  │  ¥/月 (参考) │\n"
  printf "  ├───────────────┼────────────┼────────┼────────┼──────────────┤\n"

  for machine in "${MACHINE_TYPES[@]}"; do
    local key="${region_group}:${machine}"
    local hourly="${HOURLY_PRICE[$key]}"
    local daily
    local monthly
    local jpy
    daily=$(awk   "BEGIN {printf \"%.2f\", ${hourly} * ${HOURS_PER_DAY}}")
    monthly=$(awk "BEGIN {printf \"%.2f\", ${hourly} * ${HOURS_PER_MONTH}}")
    jpy=$(awk     "BEGIN {printf \"%.0f\", ${monthly} * ${JPY_RATE}}")

    local prefix="  "
    local suffix=""
    local free_mark=""

    if [ "$machine" = "$recommended" ]; then
      prefix="${GREEN}  ►${NC}"
      suffix=" ${YELLOW}← 推奨 ★${NC}"
    fi

    if [ "$is_free_region" = "true" ] && [ "$machine" = "$FREE_TIER_MACHINE" ]; then
      free_mark="${YELLOW}(無料枠)${NC}"
    fi

    printf "  │  %-13s│ %-10s │ %-6s │ %6s │  ¥%10s  │ %b%b\n" \
      "${machine}" \
      "${MACHINE_VCPU[$machine]} / ${MACHINE_RAM[$machine]}" \
      "${hourly}" \
      "${daily}" \
      "${jpy}" \
      "${free_mark}" \
      "${suffix}"
  done

  printf "  └───────────────┴────────────┴────────┴────────┴──────────────┘\n"
  echo "  ※ インスタンス料金のみ。ディスク・ネットワーク料金は別途発生します。"
  echo "  ※ 円換算は 1 USD = 150 円の参考値です。"
  echo ""
}

# ---------------------------------------------------------------------------
# Java バージョン自動選択
# ---------------------------------------------------------------------------
function select_java_version() {
  local mc_version=$1
  local minor
  minor=$(echo "$mc_version" | cut -d. -f2)
  if   [ "$minor" -le 16 ]; then echo 11
  elif [ "$minor" -eq 17 ]; then echo 16
  elif [ "$minor" -le 20 ]; then echo 17
  else                           echo 21
  fi
}
