#!/usr/bin/env bash
# lib/05_cloudflare.sh - A レコード・SRV レコード登録
# このファイルは setup.sh から source されます。単体実行不可。

# ---------------------------------------------------------------------------
# Cloudflare DNS 登録メイン関数
# ---------------------------------------------------------------------------
function setup_cloudflare_dns() {
  step "Cloudflare DNS を設定しています..."

  verify_cloudflare_api
  _register_a_record
  _register_srv_record
}

# ---------------------------------------------------------------------------
# Cloudflare API 疎通確認
# ---------------------------------------------------------------------------
function verify_cloudflare_api() {
  info "Cloudflare API の疎通を確認しています..."

  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}")

  if [ "${response}" != "200" ]; then
    error_exit "Cloudflare API の認証に失敗しました。API Token と Zone ID を確認してください。"
  fi

  success "Cloudflare API 疎通確認完了"
}

# ---------------------------------------------------------------------------
# A レコード登録
# ---------------------------------------------------------------------------
function _register_a_record() {
  info "Cloudflare A レコードを登録しています: ${CF_DOMAIN} -> ${VM_EXTERNAL_IP}"

  # 既存レコードを確認
  local existing_id
  existing_id=$(curl -s \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${CF_DOMAIN}" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
records = data.get('result', [])
print(records[0]['id']) if records else print('')
" 2>/dev/null)

  if [ -n "${existing_id}" ]; then
    # 既存レコードを PATCH で更新
    CF_A_RECORD_ID="${existing_id}"
    curl -s -X PATCH \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"${CF_DOMAIN}\",\"content\":\"${VM_EXTERNAL_IP}\",\"ttl\":60,\"proxied\":false}" \
      "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${existing_id}" > /dev/null
    success "A レコード更新完了: ${CF_DOMAIN} -> ${VM_EXTERNAL_IP}"
  else
    # 新規 POST
    local result
    result=$(curl -s -X POST \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"${CF_DOMAIN}\",\"content\":\"${VM_EXTERNAL_IP}\",\"ttl\":60,\"proxied\":false}" \
      "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records")
    CF_A_RECORD_ID=$(echo "${result}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('result', {}).get('id', ''))
" 2>/dev/null)
    success "A レコード登録完了: ${CF_DOMAIN} -> ${VM_EXTERNAL_IP}"
  fi
}

# ---------------------------------------------------------------------------
# SRV レコード登録
# ---------------------------------------------------------------------------
function _register_srv_record() {
  info "Cloudflare SRV レコードを登録しています: ${CF_SRV_HOST}"

  # 既存 SRV レコードを確認
  local existing_srv_id
  existing_srv_id=$(curl -s \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=SRV&name=${CF_SRV_HOST}" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
records = data.get('result', [])
print(records[0]['id']) if records else print('')
" 2>/dev/null)

  local srv_data="{\"type\":\"SRV\",\"name\":\"${CF_SRV_HOST}\",\"ttl\":3600,\"data\":{\"service\":\"_minecraft\",\"proto\":\"_tcp\",\"name\":\"${CF_SRV_HOST}\",\"priority\":0,\"weight\":5,\"port\":25565,\"target\":\"${CF_DOMAIN}\"}}"

  if [ -n "${existing_srv_id}" ]; then
    curl -s -X PATCH \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "${srv_data}" \
      "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${existing_srv_id}" > /dev/null
    success "SRV レコード更新完了: ${CF_SRV_HOST}"
  else
    curl -s -X POST \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "${srv_data}" \
      "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" > /dev/null
    success "SRV レコード登録完了: ${CF_SRV_HOST}"
  fi
}
