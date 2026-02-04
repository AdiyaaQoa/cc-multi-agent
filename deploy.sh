#!/bin/bash
# ⚡ multi-agent-grid Deployment Script (Daily Startup)
# Daily Deployment Script for Multi-Agent Orchestration System
#
# Usage:
#   ./deploy.sh           # Deploy all agents (preserve previous state)
#   ./deploy.sh -c        # Clean start (reset queue)
#   ./deploy.sh -s        # Setup only (no Claude startup)
#   ./deploy.sh -h        # Show help

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Read language setting (default: ja)
LANG_SETTING="ja"
if [ -f "./config/settings.yaml" ]; then
    LANG_SETTING=$(grep "^language:" ./config/settings.yaml 2>/dev/null | awk '{print $2}' || echo "ja")
fi

# Read shell setting (default: bash)
SHELL_SETTING="bash"
if [ -f "./config/settings.yaml" ]; then
    SHELL_SETTING=$(grep "^shell:" ./config/settings.yaml 2>/dev/null | awk '{print $2}' || echo "bash")
fi

# Cyberpunk-style colored log functions
log_info() {
    echo -e "\033[1;36m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[1;32m[OK]\033[0m $1"
}

log_deploy() {
    echo -e "\033[1;35m[DEPLOY]\033[0m $1"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Prompt generation function (bash/zsh compatible)
# ───────────────────────────────────────────────────────────────────────────────
# Usage: generate_prompt "label" "color" "shell"
# Colors: red, green, blue, magenta, cyan, yellow
# ═══════════════════════════════════════════════════════════════════════════════
generate_prompt() {
    local label="$1"
    local color="$2"
    local shell_type="$3"

    if [ "$shell_type" == "zsh" ]; then
        # zsh: %F{color}%B...%b%f format
        echo "(%F{${color}}%B${label}%b%f) %F{green}%B%~%b%f%# "
    else
        # bash: \[\033[...m\] format
        local color_code
        case "$color" in
            red)     color_code="1;31" ;;
            green)   color_code="1;32" ;;
            yellow)  color_code="1;33" ;;
            blue)    color_code="1;34" ;;
            magenta) color_code="1;35" ;;
            cyan)    color_code="1;36" ;;
            *)       color_code="1;37" ;;  # white (default)
        esac
        echo "(\[\033[${color_code}m\]${label}\[\033[0m\]) \[\033[1;32m\]\w\[\033[0m\]\$ "
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Option parsing
# ═══════════════════════════════════════════════════════════════════════════════
SETUP_ONLY=false
OPEN_TERMINAL=false
CLEAN_MODE=false
COMBAT_MODE=false
STABLE_MODE=false
SHELL_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--setup-only)
            SETUP_ONLY=true
            shift
            ;;
        -c|--clean)
            CLEAN_MODE=true
            shift
            ;;
        -k|--combat)
            COMBAT_MODE=true
            shift
            ;;
        --stable|--tmux-stable)
            STABLE_MODE=true
            shift
            ;;
        -t|--terminal)
            OPEN_TERMINAL=true
            shift
            ;;
        -shell|--shell)
            if [[ -n "$2" && "$2" != -* ]]; then
                SHELL_OVERRIDE="$2"
                shift 2
            else
                echo "Error: -shell option requires bash or zsh"
                exit 1
            fi
            ;;
        -h|--help)
            echo ""
            echo "⚡ multi-agent-grid Deployment Script"
            echo ""
            echo "Usage: ./deploy.sh [options]"
            echo ""
            echo "Options:"
            echo "  -c, --clean         Reset queue and dashboard (clean start)"
            echo "                      Without this, previous state is preserved"
            echo "  -k, --combat        Combat Mode (all agents use Opus Thinking)"
            echo "                      Default is Standard Mode (Agent 1-4=Sonnet, 5-8=Opus)"
            echo "  -s, --setup-only    Setup tmux sessions only (no Claude startup)"
            echo "      --stable        Enable tmux-based stability/observability (non-breaking)"
            echo "  -t, --terminal      Open new tabs in Windows Terminal"
            echo "  -shell, --shell SH  Specify shell (bash or zsh)"
            echo "                      Default uses config/settings.yaml setting"
            echo "  -h, --help          Show this help"
            echo ""
            echo "Examples:"
            echo "  ./deploy.sh              # Deploy preserving previous state"
            echo "  ./deploy.sh -c           # Clean start (reset queue)"
            echo "  ./deploy.sh -s           # Setup only (manual Claude startup)"
            echo "  ./deploy.sh -t           # Deploy + open terminal tabs"
            echo "  ./deploy.sh -shell bash  # Deploy with bash prompts"
            echo "  ./deploy.sh -k           # Combat Mode (all Opus)"
            echo "  ./deploy.sh -c -k        # Clean start + Combat Mode"
            echo "  ./deploy.sh -shell zsh   # Deploy with zsh prompts"
            echo ""
            echo "Model Configuration:"
            echo "  Boss:        Opus (thinking disabled)"
            echo "  Operator:    Opus Thinking"
            echo "  Agent 1-4:   Sonnet Thinking"
            echo "  Agent 5-8:   Opus Thinking"
            echo ""
            echo "Formations:"
            echo "  Standard Mode (default): Agent 1-4=Sonnet Thinking, Agent 5-8=Opus Thinking"
            echo "  Combat Mode (--combat):  All Agents=Opus Thinking"
            echo ""
            echo "Aliases:"
            echo "  deploy → cd /path/to/multi-agent-grid && ./deploy.sh"
            echo "  csb    → tmux attach-session -t boss"
            echo "  csg    → tmux attach-session -t grid"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "./deploy.sh -h for help"
            exit 1
            ;;
    esac
done

# Override shell setting (command line option takes priority)
if [ -n "$SHELL_OVERRIDE" ]; then
    if [[ "$SHELL_OVERRIDE" == "bash" || "$SHELL_OVERRIDE" == "zsh" ]]; then
        SHELL_SETTING="$SHELL_OVERRIDE"
    else
        echo "Error: -shell option requires bash or zsh (given: $SHELL_OVERRIDE)"
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Optional stability helpers (tmux-native, best effort)
# ═══════════════════════════════════════════════════════════════════════════════
STABLE_STARTUP_TIMEOUT_SECONDS="${GRID_STARTUP_TIMEOUT_SECONDS:-30}"
STABLE_MONITOR_SILENCE_SECONDS="${GRID_MONITOR_SILENCE_SECONDS:-300}"

wait_for_tmux_output() {
    local target="$1"
    local label="$2"
    local needle="$3"
    local timeout="$4"

    for i in $(seq 1 "$timeout"); do
        if tmux capture-pane -t "$target" -p 2>/dev/null | grep -Fq "$needle"; then
            log_info "  └─ ${label} startup confirmed (${i}s)"
            return 0
        fi
        sleep 1
    done

    log_info "  └─ ${label} startup not confirmed (timeout ${timeout}s) — continuing"
    return 1
}

enable_tmux_stability() {
    # Avoid breaking deploy on older tmux builds: best-effort only.
    tmux set-option -g remain-on-exit on 2>/dev/null || true
    tmux set-option -g focus-events on 2>/dev/null || true

    # Visual notifications for quiet/stalled panes (window-level)
    tmux set-window-option -t grid:agents monitor-activity on 2>/dev/null || true
    tmux set-window-option -t grid:agents visual-activity on 2>/dev/null || true
    tmux set-window-option -t grid:agents monitor-silence "$STABLE_MONITOR_SILENCE_SECONDS" 2>/dev/null || true
    tmux set-window-option -t grid:agents visual-silence on 2>/dev/null || true

    # Hooks (best effort)
    tmux set-hook -g command-error 'display-message -d 0 "tmux command error on #{hook_pane}"' 2>/dev/null || true
    tmux set-hook -g pane-died 'display-message -d 0 "Pane died: #{hook_pane}"' 2>/dev/null || true
}

enable_pane_logs() {
    mkdir -p "./logs/panes" 2>/dev/null || true

    # Boss
    tmux pipe-pane -o -t boss:main "cat >> \"${SCRIPT_DIR}/logs/panes/boss.log\"" 2>/dev/null || true

    # Grid panes: op + a1-a8 (requires AGENT_IDS[] and PANE_BASE)
    for i in {0..8}; do
        local pane_index=$((PANE_BASE + i))
        local agent="${AGENT_IDS[$i]}"
        tmux pipe-pane -o -t "grid:agents.${pane_index}" "cat >> \"${SCRIPT_DIR}/logs/panes/${agent}.log\"" 2>/dev/null || true
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# Deploy banner display (Cyberpunk ASCII Art)
# ═══════════════════════════════════════════════════════════════════════════════
show_deploy_banner() {
    clear

    # Title banner (colored)
    echo ""
    echo -e "\033[1;35m╔══════════════════════════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;36m██████╗ ███████╗██████╗ ██╗      ██████╗ ██╗   ██╗██╗███╗   ██╗ ██████╗\033[0m      \033[1;35m║\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;36m██╔══██╗██╔════╝██╔══██╗██║     ██╔═══██╗╚██╗ ██╔╝██║████╗  ██║██╔════╝\033[0m      \033[1;35m║\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;36m██║  ██║█████╗  ██████╔╝██║     ██║   ██║ ╚████╔╝ ██║██╔██╗ ██║██║  ███╗\033[0m     \033[1;35m║\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;36m██║  ██║██╔══╝  ██╔═══╝ ██║     ██║   ██║  ╚██╔╝  ██║██║╚██╗██║██║   ██║\033[0m     \033[1;35m║\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;36m██████╔╝███████╗██║     ███████╗╚██████╔╝   ██║   ██║██║ ╚████║╚██████╔╝\033[0m     \033[1;35m║\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;36m╚═════╝ ╚══════╝╚═╝     ╚══════╝ ╚═════╝    ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝\033[0m      \033[1;35m║\033[0m"
    echo -e "\033[1;35m╠══════════════════════════════════════════════════════════════════════════════════╣\033[0m"
    echo -e "\033[1;35m║\033[0m       \033[1;37m>>> INITIALIZING NEURAL GRID <<<\033[0m    \033[1;36m⚡\033[0m    \033[1;33mSYSTEM ONLINE\033[0m              \033[1;35m║\033[0m"
    echo -e "\033[1;35m╚══════════════════════════════════════════════════════════════════════════════════╝\033[0m"
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # Agent Array (Cyberpunk style)
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;34m  ╔═════════════════════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;34m  ║\033[0m                    \033[1;37m[ AGENT ARRAY :: 8 UNITS DEPLOYING ]\033[0m                   \033[1;34m║\033[0m"
    echo -e "\033[1;34m  ╚═════════════════════════════════════════════════════════════════════════════╝\033[0m"

    cat << 'AGENT_EOF'

      ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐
      │ ◉ │   │ ◉ │   │ ◉ │   │ ◉ │   │ ◉ │   │ ◉ │   │ ◉ │   │ ◉ │
      │ ║ │   │ ║ │   │ ║ │   │ ║ │   │ ║ │   │ ║ │   │ ║ │   │ ║ │
      │▓▓▓│   │▓▓▓│   │▓▓▓│   │▓▓▓│   │▓▓▓│   │▓▓▓│   │▓▓▓│   │▓▓▓│
      └─┬─┘   └─┬─┘   └─┬─┘   └─┬─┘   └─┬─┘   └─┬─┘   └─┬─┘   └─┬─┘
       [A1]    [A2]    [A3]    [A4]    [A5]    [A6]    [A7]    [A8]

AGENT_EOF

    echo -e "                       \033[1;36m>>> ALL UNITS STANDING BY <<<\033[0m"
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # System Info
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;33m  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\033[0m"
    echo -e "\033[1;33m  ┃\033[0m  \033[1;37m⚡ multi-agent-grid\033[0m  ~  \033[1;36mCyberpunk Multi-Agent Orchestration System\033[0m  ~    \033[1;33m┃\033[0m"
    echo -e "\033[1;33m  ┃\033[0m                                                                           \033[1;33m┃\033[0m"
    echo -e "\033[1;33m  ┃\033[0m    \033[1;35mBoss\033[0m: Project Control    \033[1;31mOperator\033[0m: Task Management    \033[1;34mAgents\033[0m: x8       \033[1;33m┃\033[0m"
    echo -e "\033[1;33m  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\033[0m"
    echo ""
}

# Execute banner display
show_deploy_banner

echo -e "  \033[1;33m>>> Initializing Grid Infrastructure <<<\033[0m"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: Cleanup existing sessions
# ═══════════════════════════════════════════════════════════════════════════════
log_info "Terminating existing sessions..."
tmux kill-session -t grid 2>/dev/null && log_info "  └─ Grid session terminated" || log_info "  └─ No grid session found"
tmux kill-session -t boss 2>/dev/null && log_info "  └─ Boss session terminated" || log_info "  └─ No boss session found"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1.5: Backup previous records (--clean mode only, if content exists)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$CLEAN_MODE" = true ]; then
    BACKUP_DIR="./logs/backup_$(date '+%Y%m%d_%H%M%S')"
    NEED_BACKUP=false

    if [ -f "./dashboard.md" ]; then
        if grep -q "cmd_" "./dashboard.md" 2>/dev/null; then
            NEED_BACKUP=true
        fi
    fi

    if [ "$NEED_BACKUP" = true ]; then
        mkdir -p "$BACKUP_DIR" || true
        cp "./dashboard.md" "$BACKUP_DIR/" 2>/dev/null || true
        cp -r "./queue/reports" "$BACKUP_DIR/" 2>/dev/null || true
        cp -r "./queue/tasks" "$BACKUP_DIR/" 2>/dev/null || true
        cp "./queue/boss_to_op.yaml" "$BACKUP_DIR/" 2>/dev/null || true
        log_info "Backup created: $BACKUP_DIR"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: Ensure queue directories + Reset (--clean mode only)
# ═══════════════════════════════════════════════════════════════════════════════

# Create queue directories if not exists (required for first startup)
[ -d ./queue/reports ] || mkdir -p ./queue/reports
[ -d ./queue/tasks ] || mkdir -p ./queue/tasks

if [ "$CLEAN_MODE" = true ]; then
    log_info "Clearing previous task queue..."

    # Agent task files reset
    for i in {1..8}; do
        cat > ./queue/tasks/a${i}.yaml << EOF
# Agent ${i} Task File
task:
  task_id: null
  parent_cmd: null
  description: null
  target_path: null
  status: idle
  timestamp: ""
EOF
    done

    # Agent report files reset
    for i in {1..8}; do
        cat > ./queue/reports/a${i}_report.yaml << EOF
worker_id: a${i}
task_id: null
timestamp: ""
status: idle
result: null
EOF
    done

    # Queue file reset
    cat > ./queue/boss_to_op.yaml << 'EOF'
queue: []
EOF

    log_success "Queue cleared"
else
    log_info "Preserving previous queue state..."
    log_success "Queue files retained"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: Dashboard initialization (--clean mode only)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$CLEAN_MODE" = true ]; then
    log_info "Initializing dashboard..."
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

    if [ "$LANG_SETTING" = "ja" ]; then
        # Japanese only
        cat > ./dashboard.md << EOF
# 📊 Status Report
Last Updated: ${TIMESTAMP}

## 🚨 Action Required - Awaiting Client Decision
None

## 🔄 In Progress - Currently Processing
None

## ✅ Completed Tasks
| Time | Target | Mission | Result |
|------|--------|---------|--------|

## 🎯 Skill Candidates - Pending Approval
None

## 🛠️ Generated Skills
None

## ⏸️ Standby
None

## ❓ Questions
None
EOF
    else
        # English
        cat > ./dashboard.md << EOF
# 📊 Status Report
Last Updated: ${TIMESTAMP}

## 🚨 Action Required - Awaiting Client Decision
None

## 🔄 In Progress - Currently Processing
None

## ✅ Completed Tasks
| Time | Target | Mission | Result |
|------|--------|---------|--------|

## 🎯 Skill Candidates - Pending Approval
None

## 🛠️ Generated Skills
None

## ⏸️ Standby
None

## ❓ Questions
None
EOF
    fi

    log_success "  └─ Dashboard initialized (lang: $LANG_SETTING, shell: $SHELL_SETTING)"
else
    log_info "Preserving previous dashboard"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: Check tmux availability
# ═══════════════════════════════════════════════════════════════════════════════
if ! command -v tmux &> /dev/null; then
    echo ""
    echo "  ╔════════════════════════════════════════════════════════╗"
    echo "  ║  [ERROR] tmux not found!                              ║"
    echo "  ╠════════════════════════════════════════════════════════╣"
    echo "  ║  Run first_setup.sh first:                            ║"
    echo "  ║     ./first_setup.sh                                  ║"
    echo "  ╚════════════════════════════════════════════════════════╝"
    echo ""
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: Create boss session (1 pane, ensure window 0)
# ═══════════════════════════════════════════════════════════════════════════════
log_deploy "Initializing Boss terminal..."

# Create boss session if not exists
if ! tmux has-session -t boss 2>/dev/null; then
    tmux new-session -d -s boss -n main
fi

# Boss pane uses window name "main" (works with base-index 1)
BOSS_PROMPT=$(generate_prompt "Boss" "magenta" "$SHELL_SETTING")
tmux send-keys -t boss:main "cd \"$(pwd)\" && export PS1='${BOSS_PROMPT}' && clear" Enter
tmux select-pane -t boss:main -P 'bg=#1a1a2e'  # Boss dark theme
tmux set-option -p -t boss:main @agent_id "boss"

log_success "  └─ Boss terminal ready"
echo ""

# Get pane-base-index (panes start at 1 in some environments)
PANE_BASE=$(tmux show-options -gv pane-base-index 2>/dev/null || echo 0)

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5.1: Create grid session (9 panes: op + a1-a8)
# ═══════════════════════════════════════════════════════════════════════════════
log_deploy "Initializing Grid network (9 nodes)..."

# Create first pane
if ! tmux new-session -d -s grid -n "agents" 2>/dev/null; then
    echo ""
    echo "  ╔════════════════════════════════════════════════════════════╗"
    echo "  ║  [ERROR] Failed to create tmux session 'grid'            ║"
    echo "  ╠════════════════════════════════════════════════════════════╣"
    echo "  ║  An existing session may be running.                     ║"
    echo "  ║                                                          ║"
    echo "  ║  Check: tmux ls                                          ║"
    echo "  ║  Kill:  tmux kill-session -t grid                        ║"
    echo "  ╚════════════════════════════════════════════════════════════╝"
    echo ""
    exit 1
fi

# Create 3x3 grid (9 panes total)
# First split into 3 columns
tmux split-window -h -t "grid:agents"
tmux split-window -h -t "grid:agents"

# Split each column into 3 rows
tmux select-pane -t "grid:agents.${PANE_BASE}"
tmux split-window -v
tmux split-window -v

tmux select-pane -t "grid:agents.$((PANE_BASE+3))"
tmux split-window -v
tmux split-window -v

tmux select-pane -t "grid:agents.$((PANE_BASE+6))"
tmux split-window -v
tmux split-window -v

# Pane labels (for prompt: no model name)
PANE_LABELS=("op" "a1" "a2" "a3" "a4" "a5" "a6" "a7" "a8")
# Pane titles (for tmux title: with model name)
if [ "$COMBAT_MODE" = true ]; then
    PANE_TITLES=("op(Opus)" "a1(Opus)" "a2(Opus)" "a3(Opus)" "a4(Opus)" "a5(Opus)" "a6(Opus)" "a7(Opus)" "a8(Opus)")
else
    PANE_TITLES=("op(Opus)" "a1(Sonnet)" "a2(Sonnet)" "a3(Sonnet)" "a4(Sonnet)" "a5(Opus)" "a6(Opus)" "a7(Opus)" "a8(Opus)")
fi
# Color settings (op: red, agents: cyan)
PANE_COLORS=("red" "cyan" "cyan" "cyan" "cyan" "cyan" "cyan" "cyan" "cyan")

AGENT_IDS=("op" "a1" "a2" "a3" "a4" "a5" "a6" "a7" "a8")

# Model names (for pane-border-format display)
if [ "$COMBAT_MODE" = true ]; then
    MODEL_NAMES=("Opus Thinking" "Opus Thinking" "Opus Thinking" "Opus Thinking" "Opus Thinking" "Opus Thinking" "Opus Thinking" "Opus Thinking" "Opus Thinking")
else
    MODEL_NAMES=("Opus Thinking" "Sonnet Thinking" "Sonnet Thinking" "Sonnet Thinking" "Sonnet Thinking" "Opus Thinking" "Opus Thinking" "Opus Thinking" "Opus Thinking")
fi

for i in {0..8}; do
    p=$((PANE_BASE + i))
    tmux select-pane -t "grid:agents.${p}" -T "${PANE_TITLES[$i]}"
    tmux set-option -p -t "grid:agents.${p}" @agent_id "${AGENT_IDS[$i]}"
    tmux set-option -p -t "grid:agents.${p}" @model_name "${MODEL_NAMES[$i]}"
    tmux set-option -p -t "grid:agents.${p}" @task_status "idle" 2>/dev/null || true
    tmux set-option -p -t "grid:agents.${p}" @task_id "" 2>/dev/null || true
    tmux set-option -p -t "grid:agents.${p}" @last_report_time "" 2>/dev/null || true
    PROMPT_STR=$(generate_prompt "${PANE_LABELS[$i]}" "${PANE_COLORS[$i]}" "$SHELL_SETTING")
    tmux send-keys -t "grid:agents.${p}" "cd \"$(pwd)\" && export PS1='${PROMPT_STR}' && clear" Enter
done

# pane-border-format for persistent model name display
tmux set-option -t grid -w pane-border-status top
tmux set-option -t grid -w pane-border-format '#{pane_index} #{@agent_id} (#{?#{==:#{@model_name},},unknown,#{@model_name}})'

if [ "$STABLE_MODE" = true ]; then
    log_info "Enabling tmux stability/observability (best effort)..."
    enable_tmux_stability
    enable_pane_logs
fi

log_success "  └─ Grid network initialized"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: Start Claude Code (-s / --setup-only skips this)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$SETUP_ONLY" = false ]; then
    # Check Claude Code CLI availability
    if ! command -v claude &> /dev/null; then
        log_info "Warning: claude command not found"
        echo "  Run first_setup.sh:"
        echo "    ./first_setup.sh"
        exit 1
    fi

    log_deploy "Deploying Claude Code to all nodes..."

    # Boss
    tmux send-keys -t boss:main "MAX_THINKING_TOKENS=0 claude --model opus --dangerously-skip-permissions"
    tmux send-keys -t boss:main Enter
    log_info "  └─ Boss deployed"

    # Wait for stability
    sleep 1

    # Operator (pane 0): Opus Thinking
    p=$((PANE_BASE + 0))
    tmux send-keys -t "grid:agents.${p}" "claude --model opus --dangerously-skip-permissions"
    tmux send-keys -t "grid:agents.${p}" Enter
    log_info "  └─ Operator (Opus Thinking) deployed"

    if [ "$COMBAT_MODE" = true ]; then
        # Combat Mode: All agents Opus Thinking
        for i in {1..8}; do
            p=$((PANE_BASE + i))
            tmux send-keys -t "grid:agents.${p}" "claude --model opus --dangerously-skip-permissions"
            tmux send-keys -t "grid:agents.${p}" Enter
        done
        log_info "  └─ Agents 1-8 (Opus Thinking) deployed in Combat Mode"
    else
        # Standard Mode: Agent 1-4=Sonnet, Agent 5-8=Opus
        for i in {1..4}; do
            p=$((PANE_BASE + i))
            tmux send-keys -t "grid:agents.${p}" "claude --model sonnet --dangerously-skip-permissions"
            tmux send-keys -t "grid:agents.${p}" Enter
        done
        log_info "  └─ Agents 1-4 (Sonnet Thinking) deployed"

        for i in {5..8}; do
            p=$((PANE_BASE + i))
            tmux send-keys -t "grid:agents.${p}" "claude --model opus --dangerously-skip-permissions"
            tmux send-keys -t "grid:agents.${p}" Enter
        done
        log_info "  └─ Agents 5-8 (Opus Thinking) deployed"
    fi

    if [ "$COMBAT_MODE" = true ]; then
        log_success "Combat Mode activated - All Opus!"
    else
        log_success "Standard Mode deployed"
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 6.5: Load instructions to each agent
    # ═══════════════════════════════════════════════════════════════════════════
    log_deploy "Loading instructions to all nodes..."
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # Cyberpunk ASCII Art
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;35m  ┌────────────────────────────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;35m  │\033[0m                        \033[1;37m[ NEURAL LINK ESTABLISHED ]\033[0m                          \033[1;35m│\033[0m"
    echo -e "\033[1;35m  └────────────────────────────────────────────────────────────────────────────────┘\033[0m"

    cat << 'CYBER_EOF'

         ╔═══════════════════════════════════════════════════════════════╗
         ║   ████████████████████████████████████████████████████████   ║
         ║   ██                                                    ██   ║
         ║   ██    ██████╗  ██████╗  ██╗ ██████╗                   ██   ║
         ║   ██   ██╔════╝  ██╔══██╗ ██║ ██╔══██╗                  ██   ║
         ║   ██   ██║  ███╗ ██████╔╝ ██║ ██║  ██║                  ██   ║
         ║   ██   ██║   ██║ ██╔══██╗ ██║ ██║  ██║                  ██   ║
         ║   ██   ╚██████╔╝ ██║  ██║ ██║ ██████╔╝                  ██   ║
         ║   ██    ╚═════╝  ╚═╝  ╚═╝ ╚═╝ ╚═════╝   [ ONLINE ]     ██   ║
         ║   ██                                                    ██   ║
         ║   ████████████████████████████████████████████████████████   ║
         ╚═══════════════════════════════════════════════════════════════╝

CYBER_EOF

    echo ""
    echo -e "                          \033[1;36m>>> Mission ready. Awaiting orders. <<<\033[0m"
    echo ""

    echo "  Waiting for Claude Code startup (max 30 seconds)..."

    if [ "$STABLE_MODE" = true ]; then
        wait_for_tmux_output "boss:main" "Boss" "bypass permissions" "$STABLE_STARTUP_TIMEOUT_SECONDS" || true
        wait_for_tmux_output "grid:agents.${PANE_BASE}" "Operator" "bypass permissions" "$STABLE_STARTUP_TIMEOUT_SECONDS" || true
        for i in {1..8}; do
            p=$((PANE_BASE + i))
            wait_for_tmux_output "grid:agents.${p}" "Agent ${i}" "bypass permissions" "$STABLE_STARTUP_TIMEOUT_SECONDS" || true
        done
    else
        # Wait for Boss startup (max 30 seconds)
        for i in {1..30}; do
            if tmux capture-pane -t boss:main -p | grep -q "bypass permissions"; then
                echo "  └─ Boss Claude Code startup confirmed (${i}s)"
                break
            fi
            sleep 1
        done
    fi

    # Load instructions to Boss
    log_info "  └─ Loading Boss instructions..."
    tmux send-keys -t boss:main "instructions/boss.md を読んで役割を理解せよ。"
    sleep 0.5
    tmux send-keys -t boss:main Enter

    # Load instructions to Operator
    sleep 2
    log_info "  └─ Loading Operator instructions..."
    tmux send-keys -t "grid:agents.${PANE_BASE}" "instructions/operator.md を読んで役割を理解せよ。"
    sleep 0.5
    tmux send-keys -t "grid:agents.${PANE_BASE}" Enter

    # Load instructions to Agents (1-8)
    sleep 2
    log_info "  └─ Loading Agent instructions..."
    for i in {1..8}; do
        p=$((PANE_BASE + i))
        tmux send-keys -t "grid:agents.${p}" "instructions/agent.md を読んで役割を理解せよ。You are Agent ${i}."
        sleep 0.3
        tmux send-keys -t "grid:agents.${p}" Enter
        sleep 0.5
    done

    log_success "All nodes initialized with instructions"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7: Environment check / Completion message
# ═══════════════════════════════════════════════════════════════════════════════
log_info "Verifying grid status..."
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  📺 Tmux Sessions                                        │"
echo "  └──────────────────────────────────────────────────────────┘"
tmux list-sessions | sed 's/^/     /'
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  📋 Grid Formation                                        │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo "     [boss session] Boss Terminal"
echo "     ┌─────────────────────────────┐"
echo "     │  Pane 0: Boss               │  ← Project Control"
echo "     └─────────────────────────────┘"
echo ""
echo "     [grid session] Operator + Agents (3x3 = 9 panes)"
echo "     ┌─────────┬─────────┬─────────┐"
echo "     │   op    │   a3    │   a6    │"
echo "     │ (Op)    │ (Agt3)  │ (Agt6)  │"
echo "     ├─────────┼─────────┼─────────┤"
echo "     │   a1    │   a4    │   a7    │"
echo "     │ (Agt1)  │ (Agt4)  │ (Agt7)  │"
echo "     ├─────────┼─────────┼─────────┤"
echo "     │   a2    │   a5    │   a8    │"
echo "     │ (Agt2)  │ (Agt5)  │ (Agt8)  │"
echo "     └─────────┴─────────┴─────────┘"
echo ""

echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║  ⚡ DEPLOYMENT COMPLETE - GRID ONLINE                    ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""

if [ "$SETUP_ONLY" = true ]; then
    echo "  ⚠️  Setup-only mode: Claude Code not started"
    echo ""
    echo "  To manually start Claude Code:"
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │  # Start Boss                                            │"
    echo "  │  tmux send-keys -t boss:main \\                           │"
    echo "  │    'claude --dangerously-skip-permissions' Enter         │"
    echo "  │                                                          │"
    echo "  │  # Start Operator + Agents                               │"
    echo "  │  for p in \$(seq $PANE_BASE $((PANE_BASE+8))); do                                 │"
    echo "  │      tmux send-keys -t grid:agents.\$p \\                  │"
    echo "  │      'claude --dangerously-skip-permissions' Enter       │"
    echo "  │  done                                                    │"
    echo "  └──────────────────────────────────────────────────────────┘"
    echo ""
fi

echo "  Next steps:"
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  Connect to Boss terminal:                               │"
echo "  │     tmux attach-session -t boss   (or: csb)              │"
echo "  │                                                          │"
echo "  │  Monitor Grid:                                           │"
echo "  │     tmux attach-session -t grid   (or: csg)              │"
echo "  │                                                          │"
echo "  │  All agents have loaded their instructions.              │"
echo "  │  Ready to accept commands.                               │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo "  ════════════════════════════════════════════════════════════"
echo "   >>> Mission ready. Awaiting orders. <<<"
echo "  ════════════════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8: Open Windows Terminal tabs (-t option only)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$OPEN_TERMINAL" = true ]; then
    log_info "Opening Windows Terminal tabs..."

    # Check Windows Terminal availability
    if command -v wt.exe &> /dev/null; then
        wt.exe -w 0 new-tab wsl.exe -e bash -c "tmux attach-session -t boss" \; new-tab wsl.exe -e bash -c "tmux attach-session -t grid"
        log_success "  └─ Terminal tabs opened"
    else
        log_info "  └─ wt.exe not found. Attach manually."
    fi
    echo ""
fi
