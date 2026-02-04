# tmux機能拡張案（ペンディング）

> **作成日**: 2026-02-04
> **ステータス**: PENDING（保留）
> **起票者**: Boss

## 概要

tmuxの高度機能を調査し、cc-multi-agentに適用可能な改善案をまとめた。
ノースクリプト（シェルスクリプト不使用）での構築を前提とする。

---

## 即座適用可能な改善

### 1. User Options（@変数）の拡張

**現状**: `@agent_id` のみ使用
**提案**: 以下を追加

```bash
tmux set -p @task_id 'cmd_001'
tmux set -p @task_status 'in_progress'  # idle / in_progress / blocked / done
tmux set -p @last_report_time '2026-02-04T10:00:00'
```

**利点**:
- YAMLを読まずに状態取得可能
- `display-message -p '#{@task_status}'` で即座にクエリ
- ペインレベルで永続化（pane操作を跨いで維持）

---

### 2. display-message による非侵入型クエリ

**現状**: `capture-pane` でペイン出力をパース
**提案**: `display-message` で構造化データを取得

```bash
# 単一Agent状態取得
tmux display-message -t "grid:0.1" -p '#{@agent_id}: #{@task_status}'

# 全Agent一括取得
for i in {1..8}; do
  tmux display-message -t "grid:0.$i" -p "a$i: #{@task_status}"
done
```

**利点**:
- Agentの作業を中断しない
- パース不要で構造化データ取得
- capture-paneより軽量

---

### 3. Hooks（イベントフック）

**現状**: イベント駆動なし（send-keysによる通知のみ）
**提案**: tmuxネイティブのフック活用

```bash
# エラー発生時に自動通知
tmux set-hook -g command-error 'display-message "ERROR on #{hook_pane}"'

# ペイン終了時の検知
tmux set-hook -g pane-died 'display-message "Agent #{hook_pane} died"'

# タスク完了検知（@task_status変更時）
# ※ 直接のフックはないが、after-set-optionで代替可能
```

**利点**:
- ポーリング不要
- 自動エラー検知
- Agent死亡の即座検知

---

### 4. monitor-silence（沈黙検知）

**現状**: スタックしたAgentの検知手段なし
**提案**: 沈黙監視オプション

```bash
# 2分間出力がなければアラート
tmux set-option -t "grid:0.1" monitor-silence 120
```

**利点**:
- スタックしたAgentの自動検出
- ウィンドウフラグで視覚的に確認可能

---

### 5. pipe-pane（継続的ログ出力）

**現状**: ログ記録なし
**提案**: リアルタイムログ記録

```bash
# Agent出力を継続的にファイルへ
tmux pipe-pane -t "grid:0.1" "cat >> /tmp/logs/agent_a1.log"

# 停止
tmux pipe-pane -t "grid:0.1"
```

**利点**:
- デバッグ用ログの自動記録
- 外部ツールでのログ分析可能

---

## 検討価値のある機能

| 機能 | 用途 | 評価 | 優先度 |
|------|------|------|--------|
| **Control Mode** | 構造化IPC、send-keys代替 | 高性能だが学習コスト高 | 低 |
| **Format条件式** | `#{?#{==:#{@status},idle},✓,⏳}` | ダッシュボード表示に有用 | 中 |
| **Named Buffers** | メッセージキュー代替 | YAMLより軽量だが可読性低 | 低 |
| **Key Bindings** | ショートカットでAgent選択 | 人間操作の効率化 | 中 |
| **Marked Panes** | 複数Agent選択・操作 | バッチ処理に有用 | 低 |

---

## 推奨リファクタリング案

**ハイブリッドアプローチ**を推奨：

1. **@variable** でAgent状態を永続管理（YAMLを補完）
2. **display-message** でクエリ（capture-pane置換）
3. **hooks** でエラー検知（ポーリング削減）
4. **send-keys** は実際のコマンド注入のみに限定

### 実装順序（推奨）

1. @variable拡張（低リスク、即効果）
2. display-messageへの移行（中リスク、効率向上）
3. hooks導入（中リスク、イベント駆動化）
4. monitor-silence追加（低リスク、監視強化）

---

## 参考資料

- [tmux Wiki - Advanced Use](https://github.com/tmux/tmux/wiki/Advanced-Use)
- [tmux Wiki - Formats](https://github.com/tmux/tmux/wiki/Formats)
- [tmux Wiki - Control Mode](https://github.com/tmux/tmux/wiki/Control-Mode)
- [tmux(1) Man Page](https://man7.org/linux/man-pages/man1/tmux.1.html)
