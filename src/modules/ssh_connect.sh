#!/usr/bin/env bash

# ============================================================
# SH-AI SSH 连接管理业务模块
# ============================================================
# 职责: 连接建立功能
# 需求: 2.1, 2.5

# @cmd 建立 SSH ControlMaster 连接。触发:用户说 "connect <target>"。CRITICAL: 必须准确提取用户输入的 target 参数，不要修改 IP 地址、用户名或端口号。
# @alias ssh.connect
# @option --target! <user@host[:port]> SSH 目标，格式: user@host[:port]。必须准确复制用户输入的完整字符串，包括 IP 地址的所有数字。例如：用户输入 "root@192.168.11.199:212"，必须使用完全相同的字符串，不要修改任何数字或字符。
ssh_connect() {
    local target=""
    
    # 优先使用 argc 变量（让 argc 能识别参数使用）
    if [[ -n "${argc_target:-}" ]]; then
        target="${argc_target}"
    else
        # 回退到自定义解析（兼容 JSON 输入和旧版调用）
        local input="${1:-}"
        
        if [[ "$input" == \{* ]]; then
            # JSON 输入模式
            if command -v jq &>/dev/null; then
                target=$(echo "$input" | jq -r '.target // empty' 2>/dev/null)
            else
                _error "需要 jq 来解析 JSON 输入"
                return 1
            fi
        else
            # 普通参数模式
            target="$input"
        fi
    fi
    
    # Trim whitespace from target
    target=$(echo "$target" | xargs)
    
    if [[ -z "$target" ]]; then
        _error "请提供 SSH 目标 (user@host[:port])"
        _info "用法: ssh_connect user@host[:port]"
        _info "或 JSON: {\"target\": \"user@host[:port]\"}"
        return 1
    fi
    
    _output_header 2 "建立 SSH 连接"    
    # 添加元数据 - 操作类型和目标
    # 需求: 6.1, 6.2
    _add_metadata "operation" "ssh_connect"
    _add_metadata "target" "$target"
    
    # 解析 SSH 目标
    local target_info
    if ! target_info=$(_parse_ssh_target "$target"); then
        return 1
    fi
    
    # 显示连接信息
    local user host port
    eval "$target_info"
    _info "连接目标: $user@$host:$port"
    
    # 建立连接
    if _establish_connection "$target"; then
        # 设置纯数据（供模型读取，不包含格式化）
        _set_data "connection_status" "success"
        _set_data "target" "$target"
        
        # 保存最后连接的目标（用于后续命令的默认目标）
        # 注意：使用缓存系统，因为每次工具调用都是新的进程
        _save_last_connected_target "$target"
        
        # 格式化显示（仅用于终端）
        _success "SSH 连接建立成功: $target"
        
        # 自动进行设备检测
        _output_separator
        _output_header 3 "设备类型检测"        
        local device_type
        if device_type=$(_detect_device_type_ai "$target"); then
            if [[ "$device_type" == "MANUAL_INPUT_REQUIRED" ]]; then
                _warning "需要手动设置设备类型"
                _info "请使用命令: /set_device_type $target <设备类型>"
                _set_data "device_type" "unknown"
            else
                # 设置纯数据
                _set_data "device_type" "$device_type"
                # 格式化显示
                _success "设备类型: $device_type"
                # 添加设备类型元数据（用于向后兼容）
                # 需求: 6.3
                _add_metadata "device_type" "$device_type"
                local ctx_file
                if ctx_file=$(_export_device_context "$target" "$device_type"); then
                    export AI_SHELL_HOST_CONTEXT="$ctx_file"
                    _set_data "host_context" "$ctx_file"
                else
                    unset AI_SHELL_HOST_CONTEXT
                fi
            fi
        else
            _warning "设备类型检测失败，可以稍后手动设置"
            _set_data "device_type" "unknown"
            unset AI_SHELL_HOST_CONTEXT
        fi
        
        return 0
    else
        _error "SSH 连接建立失败: $target"
        return 1
    fi
}

# 导出函数
