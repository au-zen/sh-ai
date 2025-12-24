#!/usr/bin/env bash

# ============================================================
# SH-AI 直接命令执行业务模块 (增强版)
# ============================================================
# 新增功能: 原始输出模式 (/raw 命令)

# @cmd 执行远程命令并输出原始结果 (无格式)
# @alias ssh.exec_raw
# @option --target <user@host[:port]> SSH 目标(可选)。如不提供,自动使用最后连接的目标。
# @option --command! <string> 要执行的命令 (required)
ssh_exec_raw() {
    local target=""
    local command=""
    
    # 优先使用 argc 变量
    if [[ -n "${argc_command:-}" ]]; then
        target="${argc_target:-}"
        command="${argc_command}"
    else
        # 回退到自定义解析（兼容 JSON 输入和旧版调用）
        local input="${1:-}"
        
        if [[ "$input" == \{* ]]; then
            # JSON 输入模式
            if command -v jq &>/dev/null; then
                target=$(echo "$input" | jq -r '.target // empty' 2>/dev/null)
                command=$(echo "$input" | jq -r '.command // empty' 2>/dev/null)
            else
                echo "错误: 需要 jq 来解析 JSON 输入"
                return 1
            fi
        else
            # 普通参数模式
            target="$input"
            command="${2:-}"
        fi
    fi
    
    # Trim whitespace from arguments
    target=$(echo "$target" | xargs)
    command=$(echo "$command" | xargs)
    
    # 处理 AI 模型可能传递的 "null" 字符串或空字符串
    if [[ "$target" == "null" || -z "$target" ]]; then
        target=""
    fi
    
    if [[ -z "$command" ]]; then
        echo "错误: 请提供要执行的命令"
        echo "用法: ssh_exec_raw [目标主机] '<命令>'"
        echo ""
        echo "示例:"
        echo "  ssh_exec_raw 'ifconfig'"
        echo "  ssh_exec_raw root@192.168.1.1 'ip addr'"
        return 1
    fi
    
    # 如果 target 为空，尝试获取最后连接的目标
    # 注意：这是 SH-AI 本地状态，与 LLM session 无关
    if [[ -z "$target" ]]; then
        if ! target=$(_get_last_connected_target); then
            echo "错误: 未指定 SSH 目标，且无可用连接"
            echo "请先建立连接或指定目标主机"
            return 1
        fi
    fi
    
    # 启用原始输出模式 - 绕过 JSON 包装，直接输出到 stdout
    # 需求: 10.1, 10.2, 10.3, 10.4, 10.5
    _set_raw_output_mode
    
    # 检查连接状态（静默检查）
    if ! _check_connection_health "$target" 2>/dev/null; then
        echo "错误: 连接不可用，请先建立连接: /connect $target"
        return 1
    fi
    
    # 显示简单提示符 - 使用 echo 直接输出，不使用 _output() 函数
    echo "[$target]\$ $command"
    echo "----------------------------------------"
    
    # 直接执行并输出原始结果（不包装）
    _execute_remote_command "$target" "$command"
    
    local exit_code=$?
    
    # 只显示退出码 - 使用 echo 直接输出
    echo "----------------------------------------"
    echo "退出码: $exit_code"
    
    return $exit_code
}




# 导出函数（新增 ssh_exec_raw）
