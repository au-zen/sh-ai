#!/usr/bin/env bash
# ============================================================
# SH-AI SSH 重新连接模块
# ============================================================
# 职责: 重新建立 SSH 连接
# 需求: 2.4

# @cmd 重新连接 SSH。触发:用户说 'reconnect <target>'
# @alias ssh.reconnect
# @option --target <user@host[:port]> SSH 目标(可选)。如不提供,自动使用最后连接的目标。
ssh_reconnect() {
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
    
    _connect_info "正在重新连接: $target"
    
    # 先断开现有连接
    _close_connection "$target" 2>/dev/null || true
    
    # 建立新连接
    if _establish_connection "$target"; then
        _success "重新连接成功: $target"
        
        # 重新检测设备类型
        local device_type
        if device_type=$(_detect_device_type_ai "$target"); then
            _info "设备类型: $device_type"
            local ctx_file
            if ctx_file=$(_export_device_context "$target" "$device_type"); then
                export AI_SHELL_HOST_CONTEXT="$ctx_file"
                _set_data "host_context" "$ctx_file"
            else
                unset AI_SHELL_HOST_CONTEXT
            fi
        else
            unset AI_SHELL_HOST_CONTEXT
        fi
        
        return 0
    else
        _error "重新连接失败: $target"
        return 1
    fi
}

# 导出函数
export -f ssh_reconnect
