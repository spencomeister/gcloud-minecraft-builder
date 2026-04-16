#!/usr/bin/env bash
# lib/03_minecraft.sh - 各サーバー種別インストール・SpigotMC ビルド
# このファイルは setup.sh から source されます。単体実行不可。

# ---------------------------------------------------------------------------
# Minecraft サーバーインストールメイン関数
# ---------------------------------------------------------------------------
function install_minecraft_server() {
  step "Minecraft サーバー (${SERVER_TYPE}) をインストールしています..."

  # minecraft ユーザー・ディレクトリ作成
  remote_exec "sudo useradd -r -m -d /opt/minecraft -s /bin/bash minecraft 2>/dev/null || true && \
    sudo mkdir -p /opt/minecraft/${SERVER_NAME} && \
    sudo chown -R minecraft:minecraft /opt/minecraft && \
    sudo chmod 755 /opt/minecraft"

  # JVM フラグを計算
  _calculate_jvm_flags

  case "${SERVER_TYPE}" in
    vanilla)   _install_vanilla ;;
    fabric)    _install_fabric ;;
    spigot)    _install_spigot ;;
    paper)     _install_paper ;;
    *)         error_exit "不明なサーバー種別: ${SERVER_TYPE}" ;;
  esac

  # EULA 同意
  remote_exec "echo 'eula=true' | sudo tee /opt/minecraft/${SERVER_NAME}/eula.txt > /dev/null && \
    sudo chown minecraft:minecraft /opt/minecraft/${SERVER_NAME}/eula.txt && \
    sudo chmod 640 /opt/minecraft/${SERVER_NAME}/eula.txt"

  # systemd サービス登録
  _create_systemd_service

  success "Minecraft サーバーのインストール完了"
}

# ---------------------------------------------------------------------------
# JVM フラグ自動計算
# ---------------------------------------------------------------------------
function _calculate_jvm_flags() {
  info "JVM フラグを計算しています..."
  JVM_MEM=$(remote_exec "free -m | awk '/Mem:/{printf \"%d\", \$2 * 0.7}'")
  JVM_FLAGS="-Xms${JVM_MEM}M -Xmx${JVM_MEM}M \
-XX:+UseG1GC -XX:+ParallelRefProcEnabled \
-XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions \
-XX:+DisableExplicitGC -XX:+AlwaysPreTouch \
-XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 \
-XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 \
-XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 \
-XX:InitiatingHeapOccupancyPercent=15 \
-XX:G1MixedGCLiveThresholdPercent=90 \
-XX:G1RSetUpdatingPauseTimePercent=5 \
-XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem \
-XX:MaxTenuringThreshold=1"
  info "JVM メモリ割り当て: ${JVM_MEM}MB"
}

# ---------------------------------------------------------------------------
# Vanilla インストール
# ---------------------------------------------------------------------------
function _install_vanilla() {
  info "Vanilla サーバー JAR を取得しています..."

  # バージョンマニフェストから JAR URL を取得
  local jar_url
  jar_url=$(curl -s "${MOJANG_VERSION_MANIFEST}" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for v in data['versions']:
    if v['id'] == '${MC_VERSION}':
        import urllib.request
        meta = json.loads(urllib.request.urlopen(v['url']).read())
        print(meta['downloads']['server']['url'])
        break
" 2>/dev/null)

  if [ -z "${jar_url}" ]; then
    error_exit "Minecraft ${MC_VERSION} の JAR が見つかりませんでした。バージョンを確認してください。"
  fi

  remote_exec "cd /opt/minecraft/${SERVER_NAME} && \
    sudo -u minecraft curl -fsSL -o server.jar '${jar_url}'" || \
    error_exit "Vanilla JAR のダウンロードに失敗しました。"

  success "Vanilla JAR ダウンロード完了"
}

# ---------------------------------------------------------------------------
# FabricMC インストール
# ---------------------------------------------------------------------------
function _install_fabric() {
  info "FabricMC インストーラーを取得しています..."

  # 最新インストーラーバージョンを取得
  local installer_version
  installer_version=$(curl -s "${FABRIC_INSTALLER_API}" | \
    python3 -c "import sys, json; data=json.load(sys.stdin); print(data[0]['version'])" 2>/dev/null)

  if [ -z "${installer_version}" ]; then
    error_exit "Fabric インストーラーバージョンの取得に失敗しました。"
  fi

  local installer_url="https://maven.fabricmc.net/net/fabricmc/fabric-installer/${installer_version}/fabric-installer-${installer_version}.jar"

  remote_exec "cd /opt/minecraft/${SERVER_NAME} && \
    sudo -u minecraft curl -fsSL -o fabric-installer.jar '${installer_url}' && \
    sudo -u minecraft java -jar fabric-installer.jar server \
      -mcversion '${MC_VERSION}' \
      -downloadMinecraft && \
    sudo -u minecraft mv fabric-server-launch.jar server.jar 2>/dev/null || true && \
    sudo -u minecraft bash -c 'echo fabric.server.jar=server.jar > fabric-server-launcher.properties'" || \
    error_exit "FabricMC のインストールに失敗しました。"

  success "FabricMC インストール完了"
}

# ---------------------------------------------------------------------------
# SpigotMC インストール（BuildTools 自動ビルド）
# ---------------------------------------------------------------------------
function _install_spigot() {
  info "SpigotMC (BuildTools) をダウンロードしています..."

  remote_exec "cd /opt/minecraft/${SERVER_NAME} && \
    sudo -u minecraft curl -fsSL -o BuildTools.jar '${SPIGOT_BUILD_TOOLS_URL}'" || \
    error_exit "BuildTools のダウンロードに失敗しました。"

  info "SpigotMC をビルドしています（数分かかる場合があります）..."

  # ビルド実行（経過時間を表示）
  local start_time
  start_time=$(date +%s)
  remote_exec "cd /opt/minecraft/${SERVER_NAME} && \
    sudo -u minecraft java -jar BuildTools.jar --rev '${MC_VERSION}' 2>&1" || \
    error_exit "SpigotMC のビルドに失敗しました。Java バージョンまたはネットワーク環境を確認してください。"

  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))
  info "ビルド完了 (所要時間: ${elapsed}秒)"

  # 生成された JAR を配置
  remote_exec "cd /opt/minecraft/${SERVER_NAME} && \
    sudo -u minecraft cp spigot-*.jar server.jar 2>/dev/null || \
    sudo -u minecraft cp spigot*.jar server.jar" || \
    error_exit "SpigotMC JAR の配置に失敗しました。"

  success "SpigotMC インストール完了"
}

# ---------------------------------------------------------------------------
# PaperMC インストール
# ---------------------------------------------------------------------------
function _install_paper() {
  info "PaperMC の最新ビルドを取得しています..."

  # 最新ビルド番号を取得
  local builds_url="${PAPER_API_BASE}/paper/versions/${MC_VERSION}/builds"
  local latest_build
  latest_build=$(curl -s "${builds_url}" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
builds = data.get('builds', [])
if builds:
    print(builds[-1]['build'])
" 2>/dev/null)

  if [ -z "${latest_build}" ]; then
    error_exit "Minecraft ${MC_VERSION} の JAR が見つかりませんでした。バージョンを確認してください。"
  fi

  local jar_name="paper-${MC_VERSION}-${latest_build}.jar"
  local jar_url="${PAPER_API_BASE}/paper/versions/${MC_VERSION}/builds/${latest_build}/downloads/${jar_name}"

  remote_exec "cd /opt/minecraft/${SERVER_NAME} && \
    sudo -u minecraft curl -fsSL -o server.jar '${jar_url}'" || \
    error_exit "PaperMC JAR のダウンロードに失敗しました。"

  success "PaperMC インストール完了 (ビルド: ${latest_build})"

  # Velocity 導入
  if [ "${VELOCITY_ENABLED:-false}" = "true" ]; then
    _install_velocity
  fi

  # SimpleVoiceChat 導入
  if [ "${VOICECHAT_ENABLED:-false}" = "true" ]; then
    _install_voicechat
  fi
}

# ---------------------------------------------------------------------------
# Velocity プロキシインストール
# ---------------------------------------------------------------------------
function _install_velocity() {
  info "Velocity プロキシをインストールしています..."

  # 最新バージョン・ビルドを取得
  local velocity_version
  velocity_version=$(curl -s "${PAPER_API_BASE}/velocity" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
versions = data.get('versions', [])
print(versions[-1]) if versions else print('')
" 2>/dev/null)

  if [ -z "${velocity_version}" ]; then
    error_exit "Velocity のバージョン取得に失敗しました。"
  fi

  local velocity_builds_url="${PAPER_API_BASE}/velocity/versions/${velocity_version}/builds"
  local velocity_build
  velocity_build=$(curl -s "${velocity_builds_url}" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
builds = data.get('builds', [])
if builds:
    print(builds[-1]['build'])
" 2>/dev/null)

  local velocity_jar="velocity-${velocity_version}-${velocity_build}.jar"
  local velocity_url="${PAPER_API_BASE}/velocity/versions/${velocity_version}/builds/${velocity_build}/downloads/${velocity_jar}"

  remote_exec "sudo mkdir -p /opt/minecraft/velocity && \
    sudo chown -R minecraft:minecraft /opt/minecraft/velocity && \
    cd /opt/minecraft/velocity && \
    sudo -u minecraft curl -fsSL -o velocity.jar '${velocity_url}'" || \
    error_exit "Velocity JAR のダウンロードに失敗しました。"

  # Velocity systemd サービス作成
  _create_velocity_systemd_service

  success "Velocity インストール完了 (バージョン: ${velocity_version})"
}

# ---------------------------------------------------------------------------
# SimpleVoiceChat プラグインインストール
# ---------------------------------------------------------------------------
function _install_voicechat() {
  info "SimpleVoiceChat プラグインをインストールしています..."

  local plugin_url
  plugin_url=$(curl -s "${VOICECHAT_RELEASES_API}" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    name = asset['name']
    if name.endswith('.jar') and 'voicechat' in name.lower() and 'forge' not in name.lower() and 'fabric' not in name.lower():
        print(asset['browser_download_url'])
        break
" 2>/dev/null)

  if [ -z "${plugin_url}" ]; then
    warn "SimpleVoiceChat の JAR URL 取得に失敗しました。後から手動でインストールしてください。"
    return 0
  fi

  remote_exec "sudo mkdir -p /opt/minecraft/${SERVER_NAME}/plugins && \
    sudo chown -R minecraft:minecraft /opt/minecraft/${SERVER_NAME}/plugins && \
    cd /opt/minecraft/${SERVER_NAME}/plugins && \
    sudo -u minecraft curl -fsSL -o voicechat.jar '${plugin_url}'" || \
    warn "SimpleVoiceChat のダウンロードに失敗しました。後から手動でインストールしてください。"

  success "SimpleVoiceChat インストール完了"
}

# ---------------------------------------------------------------------------
# systemd サービス作成（Minecraft）
# ---------------------------------------------------------------------------
function _create_systemd_service() {
  info "systemd サービスを作成しています: minecraft-${SERVER_NAME}"

  local service_content="[Unit]
Description=Minecraft Server (${SERVER_NAME})
After=network.target tailscaled.service

[Service]
User=minecraft
WorkingDirectory=/opt/minecraft/${SERVER_NAME}
ExecStart=/usr/bin/java ${JVM_FLAGS} -jar server.jar nogui
ExecStop=/bin/kill -SIGTERM \$MAINPID
ExecStartPost=/opt/minecraft/ddns-update.sh
Restart=on-failure
RestartSec=10
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target"

  remote_exec "echo '${service_content}' | sudo tee /etc/systemd/system/minecraft-${SERVER_NAME}.service > /dev/null && \
    sudo systemctl daemon-reload && \
    sudo systemctl enable minecraft-${SERVER_NAME} && \
    sudo systemctl start minecraft-${SERVER_NAME}"

  success "systemd サービス登録・起動完了"
}

# ---------------------------------------------------------------------------
# systemd サービス作成（Velocity）
# ---------------------------------------------------------------------------
function _create_velocity_systemd_service() {
  info "Velocity systemd サービスを作成しています"

  local velocity_jvm="-Xms512M -Xmx${JVM_MEM}M \
-XX:+UseG1GC -XX:G1HeapRegionSize=4M \
-XX:+UnlockExperimentalVMOptions \
-XX:+ParallelRefProcEnabled \
-XX:+AlwaysPreTouch"

  local service_content="[Unit]
Description=Velocity Proxy
After=network.target

[Service]
User=minecraft
WorkingDirectory=/opt/minecraft/velocity
ExecStart=/usr/bin/java ${velocity_jvm} -jar velocity.jar
ExecStop=/bin/kill -SIGTERM \$MAINPID
Restart=on-failure
RestartSec=10
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target"

  remote_exec "echo '${service_content}' | sudo tee /etc/systemd/system/velocity.service > /dev/null && \
    sudo systemctl daemon-reload && \
    sudo systemctl enable velocity"

  success "Velocity systemd サービス登録完了"
}
