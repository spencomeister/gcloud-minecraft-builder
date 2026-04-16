# gcloud-minecraft-builder

Google Cloud Shell 上で Minecraft サーバーを自動構築する対話式 Bash スクリプト集です。
`git clone` して `bash setup.sh` を実行するだけで、GCP インスタンス作成から
Minecraft サーバー起動・DNS 登録・セキュリティ設定までを一括で行います。

---

## 必要なもの（事前準備）

| 項目 | 説明 |
|------|------|
| Google アカウント | Cloud Shell 利用のため |
| GCP プロジェクト | Compute Engine API の有効化権限が必要 |
| Tailscale アカウント | Auth Key を事前に発行しておくこと（Reusable・Ephemeral OFF 推奨） |
| Cloudflare アカウント | Zone:DNS:Edit 権限を持つ API Token と Zone ID |
| 管理中のドメイン | Cloudflare DNS で管理中のドメイン（例: example.com） |

---

## 実行方法

```bash
# Cloud Shell を開き、以下の 2 コマンドのみで完結します
git clone https://github.com/spencomeister/gcloud-minecraft-builder.git
bash gcloud-minecraft-builder/setup.sh
```

---

## 対話ステップ概要（全 12 ステップ）

| ステップ | 内容 |
|---------|------|
| Step  1/12 | GCP プロジェクト ID |
| Step  2/12 | サーバー名（VM 名・ディレクトリ名に使用） |
| Step  3/12 | リージョン選択（US 無料枠対象あり） |
| Step  4/12 | 想定プレイヤー数 → 料金テーブル表示 → マシンタイプ確定 |
| Step  5/12 | ディスクサイズ（推奨 50GB 以上） |
| Step  6/12 | サーバー種別（Vanilla / FabricMC / SpigotMC / PaperMC） |
| Step  7/12 | Minecraft バージョン（Java バージョン自動判定） |
| Step  8/12 | ゲーム基本設定（難易度・ゲームモード・ハードコア） |
| Step  9/12 | セキュリティ設定（ホワイトリスト・PvP・コマンドブロック・フライト） |
| Step 10/12 | Cloudflare 設定（API Token・Zone ID・ドメイン） |
| Step 11/12 | Tailscale Auth Key |
| Step 12/12 | 設定サマリー確認 → [y] 実行 / [n] 中断 |

---

## 対応サーバー種別

| 種別 | 説明 |
|------|------|
| Vanilla | Mojang 公式サーバー |
| FabricMC | MOD 軽量系（Fabric Loader） |
| SpigotMC | プラグイン系（BuildTools による自動ビルド） |
| PaperMC | 高性能プラグイン系（Velocity プロキシ・SimpleVoiceChat オプション） |

---

## リポジトリ構成

```
gcloud-minecraft-builder/
├── README.md
├── .gitignore
├── setup.sh                       # エントリーポイント（対話式メイン）
├── lib/
│   ├── common.sh                  # 共通関数・定数
│   ├── 01_gcp.sh                  # VPC・FW・VM インスタンス作成
│   ├── 02_java.sh                 # OpenJDK インストール
│   ├── 03_minecraft.sh            # サーバー種別インストール
│   ├── 04_tailscale.sh            # Tailscale 導入・設定
│   ├── 05_cloudflare.sh           # DNS レコード登録
│   ├── 06_ddns.sh                 # DDNS 更新スクリプト・Cron 設定
│   └── 07_config_gen.sh           # 設定ファイル自動生成
└── templates/
    ├── server.properties.tmpl
    ├── paper-global.yml.tmpl
    ├── paper-world-defaults.yml.tmpl
    ├── velocity.toml.tmpl
    ├── voicechat-server.properties.tmpl
    └── ddns-update.sh.tmpl
```

---

## セキュリティ

- Minecraft ポート（25565）はパブリックインターネットに一切公開しません
- SSH・Minecraft・Velocity・VoiceChat の全ポートは **Tailscale IP 帯（100.64.0.0/10）のみ**許可
- API Token・Auth Key などの機密情報はシェル変数にのみ保持し、スクリプト終了時に `unset` します

---

## よくあるエラーと対処法

| エラー | 対処法 |
|--------|--------|
| `gcloud の認証が未完了です` | `gcloud auth login` を実行してください |
| `Compute Engine API の有効化に失敗しました` | プロジェクト ID と権限を確認してください |
| `VM への SSH 接続が 5 分でタイムアウト` | GCP コンソールでファイアウォール設定を確認してください |
| `Cloudflare API の認証に失敗しました` | API Token（Zone:DNS:Edit 権限）と Zone ID を確認してください |
| `Tailscale への接続に失敗しました` | Auth Key の有効期限と権限を確認してください |
| `Minecraft X.Y.Z の JAR が見つかりません` | バージョン番号を確認してください |
| `SpigotMC のビルドに失敗しました` | Java バージョンまたはネットワーク環境を確認してください |

---

## Java バージョン自動選択

| Minecraft バージョン | OpenJDK |
|--------------------|---------|
| 〜 1.16.x | 11 |
| 1.17.x | 16 |
| 1.18.x 〜 1.20.x | 17 |
| 1.21.x 〜 | 21 |

---

## ライセンス

MIT License