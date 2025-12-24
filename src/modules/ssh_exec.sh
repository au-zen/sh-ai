#!/usr/bin/env bash

# ============================================================
# SH-AI 格式化命令执行模块（无锁 / 不卡死 / 稳定版）
# ============================================================

# @cmd 执行远程命令并输出格式化结果
# @alias ssh.exec
# @option --target <user@host[:port]> SSH 目标(可选)。如不提供,自动使用最后连接的目标。
# @option --command! <string> 要执行的命令 (required)
ssh_exec() {
    local target=""
    local command=""

    # -------------------------------
    # 1. 参数解析（与 exec_raw 完全一致）
    # -------------------------------
    if [[ -n "${argc_command:-}" ]]; then
        target="${argc_target:-}"
        command="${argc_command}"
    else
        local input="${1:-}"
        
        if [[ "$input" == \{* ]]; then
            if command -v jq &>/dev/null; then
                target=$(echo "$input" | jq -r '.target // empty')
                command=$(echo "$input" | jq -r '.command // empty')
            else
                echo "错误: 需要 jq 来解析 JSON 输入"
                return 1
            fi
        else
            target="$input"
            command="${2:-}"
        fi
    fi

    target=$(echo "$target" | xargs)
    command=$(echo "$command" | xargs)

    # null → 空
    if [[ "$target" == "null" || -z "$target" ]]; then
        target=""
    fi

    if [[ -z "$command" ]]; then
        echo "错误: 请提供要执行的命令"
        return 1
    fi

    # -------------------------------
    # 2. 自动使用最后连接的目标（与 exec_raw 一致）
    # -------------------------------
    if [[ -z "$target" ]]; then
        if ! target=$(_get_last_connected_target); then
            echo "错误: 未指定 SSH 目标，且无可用连接"
            return 1
        fi
    fi

    # -------------------------------
    # 3. 检查连接
    # -------------------------------
    if ! _check_connection_health "$target" 2>/dev/null; then
        echo "错误: 连接不可用，请先建立连接: /connect $target"
        return 1
    fi

    # -------------------------------
    # 4. 显示格式化标题
    # -------------------------------
    _output_header 2 "执行命令"
    _info "目标: $target"
    _info "命令: $command"
    _output_separator

    # -------------------------------
    # 5. 执行命令
    # -------------------------------
    local output
    output=$(_execute_remote_command "$target" "$command")
    local exit_code=$?

    # -------------------------------
    # 6. 输出结果
    # -------------------------------
    _output_header 3 "命令输出"
    _output_code "text" "$output"
    _output_separator
    
    if [[ $exit_code -eq 0 ]]; then
        _success "命令执行成功"
    else
        _error "命令执行失败"
    fi
    _info "退出码: $exit_code"
    
    # 设置结构化数据供 LLM 读取
    _set_data "command" "$command"
    _set_data "target" "$target"
    _set_data "output" "$output"
    _set_data "exit_code" "$exit_code"

    return $exit_code
}
