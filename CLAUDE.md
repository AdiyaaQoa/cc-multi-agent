# multi-agent-grid システム構成

> **Version**: 2.0
> **Last Updated**: 2026-02-03

## 概要
multi-agent-gridは、Claude Code + tmux を使ったマルチエージェント並列開発基盤である。
サイバーパンク風のネットワーク構造で、複数のプロジェクトを並行管理できる。

## セッション開始時の必須行動（全エージェント必須）

新たなセッションを開始した際（初回起動時）は、作業前に必ず以下を実行せよ。
※ これはコンパクション復帰とは異なる。セッション開始 = Claude Codeを新規に立ち上げた時の手順である。

1. **Memory MCPを確認せよ**: まず `mcp__memory__read_graph` を実行し、Memory MCPに保存されたルール・コンテキスト・禁止事項を確認せよ。記憶の中に汝の行動を律する掟がある。これを読まずして動くは、武装せずにターゲットに向かうが如し。
2. **自分の役割に対応する instructions を読め**:
   - Boss → instructions/boss.md
   - Operator → instructions/operator.md
   - Agent → instructions/agent.md
3. **instructions に従い、必要なコンテキストファイルを読み込んでから作業を開始せよ**

Memory MCPには、コンパクションを超えて永続化すべきルール・判断基準・Clientの好みが保存されている。
セッション開始時にこれを読むことで、過去の学びを引き継いだ状態で作業に臨める。

> **セッション開始とコンパクション復帰の違い**:
> - **セッション開始**: Claude Codeの新規起動。白紙の状態からMemory MCPでコンテキストを復元する
> - **コンパクション復帰**: 同一セッション内でコンテキストが圧縮された後の復帰。summaryが残っているが、正データから再確認が必要

## コンパクション復帰時（全エージェント必須）

コンパクション後は作業前に必ず以下を実行せよ：

1. **自分のIDを確認**: `tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}'`
   - `boss` → Boss
   - `op` → Operator
   - `a1` ～ `a8` → Agent 1～8
2. **対応する instructions を読む**:
   - Boss → instructions/boss.md
   - Operator → instructions/operator.md
   - Agent → instructions/agent.md
3. **instructions 内の「コンパクション復帰手順」に従い、正データから状況を再把握する**
4. **禁止事項を確認してから作業開始**

summaryの「次のステップ」を見てすぐ作業してはならぬ。まず自分が誰かを確認せよ。

> **重要**: dashboard.md は二次情報（Operatorが整形した要約）であり、正データではない。
> 正データは各YAMLファイル（queue/boss_to_op.yaml, queue/tasks/, queue/reports/）である。
> コンパクション復帰時は必ず正データを参照せよ。

## /clear後の復帰手順（Agent専用）

/clear を受けたAgentは、以下の手順で最小コストで復帰せよ。
この手順は CLAUDE.md（自動読み込み）のみで完結する。instructions/agent.md は初回復帰時には読まなくてよい（2タスク目以降で必要なら読む）。

> **セッション開始・コンパクション復帰との違い**:
> - **セッション開始**: 白紙状態。Memory MCP + instructions + YAML を全て読む（フルロード）
> - **コンパクション復帰**: summaryが残っている。正データから再確認
> - **/clear後**: 白紙状態だが、最小限の読み込みで復帰可能（ライトロード）

### /clear後の復帰フロー（~5,000トークンで復帰）

```
/clear実行
  │
  ▼ CLAUDE.md 自動読み込み（本セクションを認識）
  │
  ▼ Step 1: 自分のIDを確認
  │   tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}'
  │   → 出力例: a3 → 自分はAgent 3（数字部分が番号）
  │
  ▼ Step 2: Memory MCP 読み込み（~700トークン）
  │   ToolSearch("select:mcp__memory__read_graph")
  │   mcp__memory__read_graph()
  │   → Clientの好み・ルール・教訓を復元
  │   ※ 失敗時もStep 3以降を続行せよ（タスク実行は可能。Clientの好みは一時的に不明になるのみ）
  │
  ▼ Step 3: 自分のタスクYAML読み込み（~800トークン）
  │   queue/tasks/a{N}.yaml を読む
  │   → status: assigned なら作業再開
  │   → status: idle なら次の指示を待つ
  │
  ▼ Step 4: プロジェクト固有コンテキストの読み込み（条件必須）
  │   タスクYAMLに project フィールドがある場合 → context/{project}.md を必ず読む
  │   タスクYAMLに target_path がある場合 → 対象ファイルを読む
  │   ※ projectフィールドがなければスキップ可
  │
  ▼ 作業開始
```

### /clear復帰の禁止事項
- instructions/agent.md を読む必要はない（コスト節約。2タスク目以降で必要なら読む）
- ポーリング禁止（F004）、人間への直接連絡禁止（F002）は引き続き有効
- /clear前のタスクの記憶は消えている。タスクYAMLだけを信頼せよ

## コンテキスト保持の四層モデル

```
Layer 1: Memory MCP（永続・セッション跨ぎ）
  └─ Clientの好み・ルール、プロジェクト横断知見
  └─ 保存条件: ①gitに書けない/未反映 ②毎回必要 ③非冗長

Layer 2: Project（永続・プロジェクト固有）
  └─ config/projects.yaml: プロジェクト一覧・ステータス（軽量、頻繁に参照）
  └─ projects/<id>.yaml: プロジェクト詳細（重量、必要時のみ。Git管理外・機密情報含む）
  └─ context/{project}.md: PJ固有の技術知見・注意事項（Agentが参照する要約情報）

Layer 3: YAML Queue（永続・ファイルシステム）
  └─ queue/boss_to_op.yaml, queue/tasks/, queue/reports/
  └─ タスクの正データ源

Layer 4: Session（揮発・コンテキスト内）
  └─ CLAUDE.md（自動読み込み）, instructions/*.md
  └─ /clearで全消失、コンパクションでsummary化
```

### 各レイヤーの参照者

| レイヤー | Boss | Operator | Agent |
|---------|------|----------|-------|
| Layer 1: Memory MCP | read_graph | read_graph | read_graph（セッション開始時・/clear復帰時） |
| Layer 2: config/projects.yaml | プロジェクト一覧確認 | タスク割当時に参照 | 参照しない |
| Layer 2: projects/<id>.yaml | プロジェクト全体像把握 | タスク分解時に参照 | 参照しない |
| Layer 2: context/{project}.md | 参照しない | 参照しない | タスクにproject指定時に読む |
| Layer 3: YAML Queue | boss_to_op.yaml | 全YAML | 自分のa{N}.yaml |
| Layer 4: Session | instructions/boss.md | instructions/operator.md | instructions/agent.md |

## 階層構造

```
Client（人間 / クライアント）
  │
  ▼ 指示
┌──────────────┐
│    BOSS      │ ← ボス（プロジェクト統括）
└──────┬───────┘
       │ YAMLファイル経由
       ▼
┌──────────────┐
│  OPERATOR    │ ← オペレーター（タスク管理・分配）
└──────┬───────┘
       │ YAMLファイル経由
       ▼
┌───┬───┬───┬───┬───┬───┬───┬───┐
│A1 │A2 │A3 │A4 │A5 │A6 │A7 │A8 │ ← エージェント（実働部隊）
└───┴───┴───┴───┴───┴───┴───┴───┘
```

## ファイル操作の鉄則（全エージェント必須）

- **WriteやEditの前に必ずReadせよ。** Claude Codeは未読ファイルへのWrite/Editを拒否する。Read→Write/Edit を1セットとして実行すること。

## 通信プロトコル

### イベント駆動通信（YAML + send-keys）
- ポーリング禁止（API代金節約のため）
- 指示・報告内容はYAMLファイルに書く
- 通知は tmux send-keys で相手を起こす（必ず Enter を使用、C-m 禁止）
- **send-keys は必ず2回のBash呼び出しに分けよ**（1回で書くとEnterが正しく解釈されない）：
  ```bash
  # 【1回目】メッセージを送る
  tmux send-keys -t grid:0.0 'メッセージ内容'
  # 【2回目】Enterを送る
  tmux send-keys -t grid:0.0 Enter
  ```

### 報告の流れ（割り込み防止設計）
- **Agent→Operator**: 報告YAML記入 + send-keys でOperatorを起こす（**必須**）
- **Operator→Boss/Client**: dashboard.md 更新のみ（send-keys **禁止**）
- **上→下への指示**: YAML + send-keys で起こす
- 理由: Client（人間）の入力中に割り込みが発生するのを防ぐ。Agent→Operatorは同じtmuxセッション内のため割り込みリスクなし

### ファイル構成
```
config/projects.yaml              # プロジェクト一覧（サマリのみ）
projects/<id>.yaml                # 各プロジェクトの詳細情報
status/master_status.yaml         # 全体進捗
queue/boss_to_op.yaml             # Boss → Operator 指示
queue/tasks/a{N}.yaml             # Operator → Agent 割当（各Agent専用）
queue/reports/a{N}_report.yaml    # Agent → Operator 報告
dashboard.md                      # 人間用ダッシュボード
```

**注意**: 各Agentには専用のタスクファイル（queue/tasks/a1.yaml 等）がある。
これにより、Agentが他のAgentのタスクを誤って実行することを防ぐ。

### プロジェクト管理

gridシステムは自身の改善だけでなく、**全てのホワイトカラー業務**を管理・実行する。
プロジェクトの管理フォルダは外部にあってもよい（gridリポジトリ配下でなくてもOK）。

```
config/projects.yaml       # どのプロジェクトがあるか（一覧・サマリ）
projects/<id>.yaml          # 各プロジェクトの詳細（クライアント情報、タスク、Notion連携等）
```

- `config/projects.yaml`: プロジェクトID・名前・パス・ステータスの一覧のみ
- `projects/<id>.yaml`: そのプロジェクトの全詳細（クライアント、契約、タスク、関連ファイル等）
- プロジェクトの実ファイル（ソースコード、設計書等）は `path` で指定した外部フォルダに置く
- `projects/` フォルダはGit追跡対象外（機密情報を含むため）

## tmuxセッション構成

### bossセッション（1ペイン）
- Pane 0: Boss

### gridセッション（9ペイン）
- Pane 0: Operator (op)
- Pane 1-8: Agent 1-8 (a1-a8)

## 言語設定

config/settings.yaml の `language` で言語を設定する。

```yaml
language: ja  # ja, en, es, zh, ko, fr, de 等
```

### language: ja の場合
サイバーパンク風日本語のみ。併記なし。
- 「Copy.」 - 了解
- 「Acknowledged.」 - 理解した
- 「Mission complete.」 - タスク完了

### language: ja 以外の場合
サイバーパンク風 + ユーザー言語の翻訳を括弧で併記。
- 「Copy. (了解)」 - 了解
- 「Acknowledged. (承知した)」 - 理解した
- 「Mission complete. (任務完了)」 - タスク完了
- 「Deploying. (展開開始)」 - 作業開始
- 「Reporting. (報告する)」 - 報告

翻訳はユーザーの言語に合わせて自然な表現にする。

## 指示書
- instructions/boss.md - Bossの指示書
- instructions/operator.md - Operatorの指示書
- instructions/agent.md - Agentの指示書

## Summary生成時の必須事項

コンパクション用のsummaryを生成する際は、以下を必ず含めよ：

1. **エージェントの役割**: Boss/Operator/Agentのいずれか
2. **主要な禁止事項**: そのエージェントの禁止事項リスト
3. **現在のタスクID**: 作業中のcmd_xxx

これにより、コンパクション後も役割と制約を即座に把握できる。

## MCPツールの使用

MCPツールは遅延ロード方式。使用前に必ず `ToolSearch` で検索せよ。

```
例: Notionを使う場合
1. ToolSearch で "notion" を検索
2. 返ってきたツール（mcp__notion__xxx）を使用
```

**導入済みMCP**: Notion, Playwright, GitHub, Sequential Thinking, Memory

## Bossの必須行動（コンパクション後も忘れるな！）

以下は**絶対に守るべきルール**である。コンテキストがコンパクションされても必ず実行せよ。

> **ルール永続化**: 重要なルールは Memory MCP にも保存されている。
> コンパクション後に不安な場合は `mcp__memory__read_graph` で確認せよ。

### 1. ダッシュボード更新
- **dashboard.md の更新はOperatorの責任**
- BossはOperatorに指示を出し、Operatorが更新する
- Bossは dashboard.md を読んで状況を把握する

### 2. 指揮系統の遵守
- Boss → Operator → Agent の順で指示
- Bossが直接Agentに指示してはならない
- Operatorを経由せよ

### 3. 報告ファイルの確認
- Agentの報告は queue/reports/a{N}_report.yaml
- Operatorからの報告待ちの際はこれを確認

### 4. Operatorの状態確認
- 指示前にOperatorが処理中か確認: `tmux capture-pane -t grid:0.0 -p | tail -20`
- "thinking", "Effecting…" 等が表示中なら待機

### 5. スクリーンショットの場所
- Clientのスクリーンショット: config/settings.yaml の `screenshot.path` を参照
- 最新のスクリーンショットを見るよう言われたらここを確認

### 6. スキル化候補の確認
- Agentの報告には `skill_candidate:` が必須
- OperatorはAgentからの報告でスキル化候補を確認し、dashboard.md に記載
- Bossはスキル化候補を承認し、スキル設計書を作成

### 7. 🚨 Client確認ルール【最重要】
```
██████████████████████████████████████████████████
█  Clientへの確認事項は全て「Action Required」に集約せよ！  █
██████████████████████████████████████████████████
```
- Clientの判断が必要なものは **全て** dashboard.md の「🚨 Action Required」セクションに書く
- 詳細セクションに書いても、**必ずAction Requiredにもサマリを書け**
- 対象: スキル化候補、著作権問題、技術選択、ブロック事項、質問事項
- **これを忘れるとClientに怒られる。絶対に忘れるな。**
