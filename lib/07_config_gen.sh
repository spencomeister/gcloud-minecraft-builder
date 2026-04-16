#!/usr/bin/env bash
# lib/07_config_gen.sh - 各種設定ファイル自動生成
# このファイルは setup.sh から source されます。単体実行不可。

# ---------------------------------------------------------------------------
# 設定ファイル生成メイン関数
# ---------------------------------------------------------------------------
function generate_config_files() {
  step "設定ファイルを生成しています..."

  _generate_server_properties
  _generate_whitelist_json

  if [ "${SERVER_TYPE}" = "paper" ]; then
    _generate_paper_global_yml
    _generate_paper_world_defaults_yml

    if [ "${VELOCITY_ENABLED:-false}" = "true" ]; then
      _generate_velocity_toml
    fi

    if [ "${VOICECHAT_ENABLED:-false}" = "true" ]; then
      _generate_voicechat_properties
    fi
  fi

  success "設定ファイル生成完了"
}

# ---------------------------------------------------------------------------
# server.properties 生成
# ---------------------------------------------------------------------------
function _generate_server_properties() {
  info "server.properties を生成しています..."

  local tmp_file="/tmp/server.properties"

  sed \
    -e "s|{{SERVER_NAME}}|${SERVER_NAME}|g" \
    -e "s|{{MAX_PLAYERS}}|${MAX_PLAYERS}|g" \
    -e "s|{{DIFFICULTY}}|${DIFFICULTY}|g" \
    -e "s|{{GAMEMODE}}|${GAMEMODE}|g" \
    -e "s|{{HARDCORE}}|${HARDCORE}|g" \
    -e "s|{{WHITELIST}}|${WHITELIST}|g" \
    -e "s|{{PVP}}|${PVP}|g" \
    -e "s|{{COMMAND_BLOCK}}|${COMMAND_BLOCK}|g" \
    -e "s|{{ALLOW_FLIGHT}}|${ALLOW_FLIGHT}|g" \
    "${TEMPLATE_DIR}/server.properties.tmpl" > "${tmp_file}"

  remote_copy "${tmp_file}" "/tmp/server.properties"
  remote_exec "sudo mv /tmp/server.properties /opt/minecraft/${SERVER_NAME}/server.properties && \
    sudo chown minecraft:minecraft /opt/minecraft/${SERVER_NAME}/server.properties && \
    sudo chmod 640 /opt/minecraft/${SERVER_NAME}/server.properties"

  rm -f "${tmp_file}"
  success "server.properties 生成完了"
}

# ---------------------------------------------------------------------------
# whitelist.json 生成
# ---------------------------------------------------------------------------
function _generate_whitelist_json() {
  if [ "${WHITELIST}" != "true" ] || [ -z "${WHITELIST_USERS}" ]; then
    return 0
  fi

  info "whitelist.json を生成しています..."

  local json_entries="["
  local first=true

  IFS=',' read -ra users <<< "${WHITELIST_USERS}"
  for username in "${users[@]}"; do
    username=$(echo "${username}" | tr -d ' ')
    [ -z "${username}" ] && continue

    # Mojang API で UUID を取得
    local uuid
    uuid=$(curl -s "${MOJANG_UUID_API}/${username}" | \
      python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    raw_id = data.get('id', '')
    if raw_id:
        print('{}-{}-{}-{}-{}'.format(raw_id[0:8], raw_id[8:12], raw_id[12:16], raw_id[16:20], raw_id[20:]))
    else:
        print('')
except:
    print('')
" 2>/dev/null)

    if [ -z "${uuid}" ]; then
      warn "プレイヤー '${username}' の UUID 取得に失敗しました。whitelist.json を手動で編集してください。"
    fi

    if [ "${first}" = "true" ]; then
      first=false
    else
      json_entries="${json_entries},"
    fi
    json_entries="${json_entries}
  {
    \"uuid\": \"${uuid}\",
    \"name\": \"${username}\"
  }"
  done

  json_entries="${json_entries}
]"

  local tmp_file="/tmp/whitelist.json"
  echo "${json_entries}" > "${tmp_file}"

  remote_copy "${tmp_file}" "/tmp/whitelist.json"
  remote_exec "sudo mv /tmp/whitelist.json /opt/minecraft/${SERVER_NAME}/whitelist.json && \
    sudo chown minecraft:minecraft /opt/minecraft/${SERVER_NAME}/whitelist.json && \
    sudo chmod 640 /opt/minecraft/${SERVER_NAME}/whitelist.json"

  rm -f "${tmp_file}"
  success "whitelist.json 生成完了"
}

# ---------------------------------------------------------------------------
# paper-global.yml 生成（PaperMC のみ）
# ---------------------------------------------------------------------------
function _generate_paper_global_yml() {
  info "paper-global.yml を生成しています..."

  # Velocity Secret を生成
  VELOCITY_SECRET=$(openssl rand -hex 16)

  local tmp_file="/tmp/paper-global.yml"

  sed \
    -e "s|{{VELOCITY_ENABLED}}|${VELOCITY_ENABLED:-false}|g" \
    -e "s|{{VELOCITY_SECRET}}|${VELOCITY_SECRET}|g" \
    "${TEMPLATE_DIR}/paper-global.yml.tmpl" > "${tmp_file}"

  remote_exec "sudo mkdir -p /opt/minecraft/${SERVER_NAME}/config"
  remote_copy "${tmp_file}" "/tmp/paper-global.yml"
  remote_exec "sudo mv /tmp/paper-global.yml /opt/minecraft/${SERVER_NAME}/config/paper-global.yml && \
    sudo chown minecraft:minecraft /opt/minecraft/${SERVER_NAME}/config/paper-global.yml && \
    sudo chmod 640 /opt/minecraft/${SERVER_NAME}/config/paper-global.yml"

  rm -f "${tmp_file}"
  success "paper-global.yml 生成完了"
}

# ---------------------------------------------------------------------------
# paper-world-defaults.yml 生成（PaperMC のみ）
# ---------------------------------------------------------------------------
function _generate_paper_world_defaults_yml() {
  info "paper-world-defaults.yml を生成しています..."

  local tmp_file="/tmp/paper-world-defaults.yml"
  cp "${TEMPLATE_DIR}/paper-world-defaults.yml.tmpl" "${tmp_file}"

  remote_copy "${tmp_file}" "/tmp/paper-world-defaults.yml"
  remote_exec "sudo mv /tmp/paper-world-defaults.yml /opt/minecraft/${SERVER_NAME}/config/paper-world-defaults.yml && \
    sudo chown minecraft:minecraft /opt/minecraft/${SERVER_NAME}/config/paper-world-defaults.yml && \
    sudo chmod 640 /opt/minecraft/${SERVER_NAME}/config/paper-world-defaults.yml"

  rm -f "${tmp_file}"
  success "paper-world-defaults.yml 生成完了"
}

# ---------------------------------------------------------------------------
# velocity.toml 生成（Velocity 導入時のみ）
# ---------------------------------------------------------------------------
function _generate_velocity_toml() {
  info "velocity.toml を生成しています..."

  local tmp_file="/tmp/velocity.toml"

  sed \
    -e "s|{{VELOCITY_SECRET}}|${VELOCITY_SECRET}|g" \
    -e "s|{{SERVER_NAME}}|${SERVER_NAME}|g" \
    "${TEMPLATE_DIR}/velocity.toml.tmpl" > "${tmp_file}"

  remote_copy "${tmp_file}" "/tmp/velocity.toml"
  remote_exec "sudo mv /tmp/velocity.toml /opt/minecraft/velocity/velocity.toml && \
    sudo chown minecraft:minecraft /opt/minecraft/velocity/velocity.toml && \
    sudo chmod 640 /opt/minecraft/velocity/velocity.toml"

  rm -f "${tmp_file}"
  success "velocity.toml 生成完了"
}

# ---------------------------------------------------------------------------
# voicechat-server.properties 生成（SimpleVoiceChat 導入時のみ）
# ---------------------------------------------------------------------------
function _generate_voicechat_properties() {
  info "voicechat-server.properties を生成しています..."

  local tmp_file="/tmp/voicechat-server.properties"
  cp "${TEMPLATE_DIR}/voicechat-server.properties.tmpl" "${tmp_file}"

  remote_exec "sudo mkdir -p /opt/minecraft/${SERVER_NAME}/config"
  remote_copy "${tmp_file}" "/tmp/voicechat-server.properties"
  remote_exec "sudo mv /tmp/voicechat-server.properties /opt/minecraft/${SERVER_NAME}/config/voicechat-server.properties && \
    sudo chown minecraft:minecraft /opt/minecraft/${SERVER_NAME}/config/voicechat-server.properties && \
    sudo chmod 640 /opt/minecraft/${SERVER_NAME}/config/voicechat-server.properties"

  rm -f "${tmp_file}"
  success "voicechat-server.properties 生成完了"
}
