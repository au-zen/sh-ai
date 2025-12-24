#!/usr/bin/env bash
# ============================================================
# SH-AI SSH 断开连接模块
# ============================================================
# 职责: 断开指定的 SSH 连接
# 需求: 2.4

# @cmd 断开 SSH 连接。触发:用户说 'disconnect <target>'
# @alias ssh.disconnect
# @option --target <user@host[:port]> SSH 目标(可选)。如不提供,自动使用最后连接的目标。
ssh_disconnect() {
    local target=""
    
    # 优先使用 argc 变量
    if [[ -n "${argc_target:-}" ]]; then
        target="${argc_target}"
    else
        # 回退到自定义解析
        local input="${1:-}"
        
        if [[ "$input" == \{* ]]; then
            if command -v jq &>/dev/null; then
                target=$(echo "$input" | jq -r '.target // empty' 2>/dev/null)
            fi
        else
            target="$input"
        fi
    fi
    
    # Trim whitespace from target
    target=$(echo "$target" | xargs)
    
    # 处理 AI 模型可能传递的 "null" 字符串或空字符串
    if [[ "$target" == "null" || -z "$target" ]]; then
        target=""
    fi
    
    # 如果 target 为空，尝试获取最后连接的目标
    if [[ -z "$target" ]]; then
        if target=$(_get_last_connected_target); then
            _info "使用最后连接的目标: $target"
        else
            _error "请提供 SSH 目标 (user@host[:port])"
            return 1
        fi
    fi
    
    _disconnect_info "正在断开连接: $target"
    
    # 调用核心模块的关闭连接函数
    if _close_connection "$target"; then
        _success "连接已断开: $target"
        
        # 清除设备类型缓存
        _clear_device_cache "$target" 2>/dev/null || true
        
        return 0
    else
        _error "断开连接失败: $target"
        return 1
    fi
}

# 导出函数
export -f ssh_disconnect
