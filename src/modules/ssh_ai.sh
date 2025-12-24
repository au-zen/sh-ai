#!/usr/bin/env bash

# ============================================================
# SH-AI  —— 方案 C：最稳定版本
# 无 Session、无模型记忆依赖、一次一调用、极简可靠
# ============================================================

# @cmd AI 智能命令生成与执行
# @alias ssh.shai
# @option --intent! <string> 用户自然语言意图 (required)
# @option --target <user@host[:port]> SSH 目标(可选)。如不提供,自动使用最后连接的目标。
ssh_ai() {
    local intent=""
    local target=""

    # -------------------------
    # 参数解析（与 ssh_exec_raw 同风格）
    # -------------------------
    if [[ -n "${argc_intent:-}" ]]; then
        intent="${argc_intent}"
        target="${argc_target:-}"
    else
        # 普通或 JSON
        local input="${1:-}"
        if [[ "$input" == \{* ]]; then
            if ! command -v jq &>/dev/null; then
                echo "ERROR: ssh_ai requires jq for JSON input" >&2
                return 1
            fi
            intent=$(echo "$input" | jq -r '.intent // empty')
            target=$(echo "$input" | jq -r '.target // empty')
        else
            intent="$input"
            target="${2:-}"
        fi
    fi

    # 清理参数
    intent=$(echo "$intent" | xargs)
    target=$(echo "$target" | xargs)

    [[ "$target" == "null" ]] && target=""

    if [[ -z "$intent" ]]; then
        echo "ERROR: Missing intent" >&2
        return 1
    fi

    # -------------------------
    # 自动取最后连接的 target
    # -------------------------
    if [[ -z "$target" ]]; then
        if ! target=$(_get_last_connected_target); then
            echo "ERROR: No active SSH target. Use /connect first" >&2
            return 1
        fi
    fi

    # -------------------------
    # 检查连接状态
    # -------------------------
    if ! _check_connection_health "$target" 2>/dev/null; then
        echo "ERROR: Connection to '$target' is down" >&2
    fi

    _output_header 2 "AI 命令生成"
    _info "Intent     : $intent"
    _info "Target     : $target"
    _output_separator

    local device_type="unknown"
    if device_type=$(_get_cached_device_type "$target" 2>/dev/null); then
        [[ -z "$device_type" ]] && device_type="unknown"
    fi

    # ============================================================
    # 1) 使用 AI 生成命令
    # ============================================================
    local req
    req=$(cat <<EOF
{
    "type":"command_generation",
    "intent":"$intent",
    "target":"$target"
}
EOF
)

    local ai_raw=""
    _warning "AI command generation disabled; using rule-based fallback"
    local ai_cmd=""
    ai_cmd=$(_generate_command_by_rules "$intent" "$device_type" "$target")

    if [[ -z "$ai_cmd" ]]; then
        _error "Unable to generate valid command"
        return 1
    fi

    _output_header 3 "Generated Command"
    _output_code "bash" "$ai_cmd"
    _output_separator

    # ============================================================
    # 3) 安全检查
    # ============================================================
    if _is_dangerous_command "$ai_cmd"; then
        echo "ERROR: dangerous command detected!" >&2
        echo "Command: $ai_cmd"
        return 1
    fi

    # ============================================================
    # 4) 使用 ssh_exec_raw 执行
    # ============================================================
    _output_header 3 "执行中"
    local result=""
    if ! result=$(ssh_exec_raw "$target" "$ai_cmd" 2>&1); then
        _error "Execution failed"
        _output "$result"
        return 1
    fi

    # ============================================================
    # 5) 显示结果
    # ============================================================
    _output_header 3 "执行结果"
    _output "$result"
    
    # 设置结构化数据
    _set_data "intent" "$intent"
    _set_data "command" "$ai_cmd"
    _set_data "target" "$target"
    _set_data "result" "$result"

    return 0
}

# ============================================================
# AI 命令清洗（最稳定版本）
# 保留你之前的，但删掉了不必要的逻辑
# ============================================================
_clean_ai_command_output() {
    local txt="$1"

    txt=$(echo "$txt" | sed '/^```/d')
    txt=$(echo "$txt" | sed 's/^bash:[[:space:]]*//' | sed 's/^sh:[[:space:]]*//')
    txt=$(echo "$txt" | sed 's/^[$#][[:space:]]*//')

    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        line=$(echo "$line" | sed 's/^[$#][[:space:]]*//')
        line=$(echo "$line" | xargs)
        if [[ "$line" =~ ^[a-zA-Z0-9_/.-] ]]; then
            echo "$line"
            return 0
        fi
    done <<< "$txt"

    return 1
}

export -f ssh_ai _clean_ai_command_output
