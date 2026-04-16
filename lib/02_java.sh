#!/usr/bin/env bash
# lib/02_java.sh - OpenJDK バージョン自動選択・インストール
# このファイルは setup.sh から source されます。単体実行不可。

# ---------------------------------------------------------------------------
# Java インストールメイン関数（VM 上で実行）
# ---------------------------------------------------------------------------
function install_java_on_vm() {
  step "Java (OpenJDK ${JAVA_VERSION}) をインストールしています..."

  remote_exec "sudo apt-get update -y && \
    sudo apt-get install -y openjdk-${JAVA_VERSION}-jre-headless" || \
    error_exit "Java のインストールに失敗しました。"

  # インストール確認
  local installed_version
  installed_version=$(remote_exec "java -version 2>&1 | head -1" 2>/dev/null || echo "")
  success "Java インストール完了: ${installed_version}"
}
