#!/usr/bin/env bash

# ============================================================
# SH-AI SSH 状态查看业务模块
# ============================================================
# 职责: SSH 连接状态查看功能
# 需求: 2.4, 3.1, 3.2, 3.3

# 显示单个目标的连接状态
_show_single_status() {
    local target="$1"
    
    _output_header 2 "连接状态"    
    # 添加元数据 - 操作类型和目标
    # 需求: 6.1, 6.2
    _add_metadata "operation" "ssh_status"
    _add_metadata "target" "$target"
    
    # 获取连接状态
    local status_info
    status_info=$(_get_connection_status "$target")
    
    # 解析状态信息
    eval "$status_info"
    
    # 创建状态表格
    declare -A status_table
    status_table["目标"]="$target"
    status_table["状态"]="$status"
    status_table["套接字存在"]="$socket_exists"
    status_table["健康检查"]="$health_check"
    status_table["控制套接字"]="$control_socket"
    
    if [[ "$connection_time" != "unknown" ]]; then
        local formatted_time
        formatted_time=$(date -d "@$connection_time" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
        status_table["连接时间"]="$formatted_time"
    else
        status_table["连接时间"]="未知"
    fi
    
    _output_table status_table
    
    # 显示设备类型信息
    local device_type
    if device_type=$(_get_cached_device_type "$target"); then
        _info "设备类型: $device_type"
    else
        _warning "设备类型未知"
    fi
    
    # 添加连接状态元数据
    # 需求: 6.2
    _add_metadata "connection_status" "$status"
    
    # 根据状态提供建议
    case "$status" in
        "connected")
            _output_status "success" "连接正常"
            ;;
        "stale")
            _output_status "warning" "连接可能已断开，建议重新连接"
            ;;
        "disconnected")
            _output_status "error" "未连接"
            ;;
    esac
}

# 显示所有已连接主机的状态（优化版：仅检查套接字存在性）
_show_all_connected_status() {
    _output_header 2 "所有连接状态"    
    # 添加元数据 - 操作类型
    # 需求: 6.1
    _add_metadata "operation" "ssh_status_all"
    
    local registry_file="$SSH_CONTROL_DIR/connection_registry"
    local found_connected=false
    local connection_id remaining timestamp target
    
    if [[ -f "$registry_file" ]]; then
        while read -r line; do
            [[ -n "$line" ]] || continue
            
            # 解析注册表条目
            connection_id="${line%%:*}"
            remaining="${line#*:}"
            timestamp="${remaining##*:}"
            target="${remaining%:*}"
            
            [[ -n "$connection_id" && -n "$target" ]] || continue
            
            # 快速检查：只检查套接字文件是否存在（不执行 SSH 命令）
            local control_socket
            control_socket=$(_get_control_socket "$target")
            
            if [[ -S "$control_socket" ]]; then
                found_connected=true
                
                _output_separator
                _output_header 3 "$target"
                _output ""
                
                # 创建状态表格
                declare -A status_table
                status_table["状态"]="已连接"
                
                # 格式化连接时间
                local connection_time
                connection_time=$(stat -c %Y "$control_socket" 2>/dev/null || echo "unknown")
                if [[ "$connection_time" != "unknown" ]]; then
                    local formatted_time
                    formatted_time=$(date -d "@$connection_time" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
                    status_table["连接时间"]="$formatted_time"
                else
                    status_table["连接时间"]="未知"
                fi
                
                # 获取设备类型
                local device_type="未知"
                if device_type=$(_get_cached_device_type "$target" 2>/dev/null); then
                    [[ -n "$device_type" ]] || device_type="未知"
                fi
                status_table["设备类型"]="$device_type"
                
                status_table["控制套接字"]="$control_socket"
                
                _output_table status_table
                _success "套接字存在"
            fi
            
        done < "$registry_file"
    fi
    
    if [[ "$found_connected" != "true" ]]; then
        _output ""
        _info "当前没有已连接的 SSH 主机"
        _info "使用 /connect <目标> 建立新连接"
        _info "使用 /list 查看所有连接状态"
    fi
}

# @cmd 显示 SSH 连接状态
# @alias ssh.status
# @option --target <user@host[:port]> SSH 目标(可选)。如不提供,显示所有连接。
ssh_status() {
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
    
    # Handle case where target might be empty string or whitespace
    target=$(echo "$target" | xargs)
    
    # 处理 AI 模型可能传递的 "null" 字符串
    if [[ "$target" == "null" ]]; then
        target=""
    fi
    
    if [[ -z "$target" ]]; then
        # 没有提供目标参数，显示所有已连接的主机状态
        _show_all_connected_status
    else
        # 提供了目标参数，显示单个主机状态
        _show_single_status "$target"
    fi
    
    return 0
}

# 导出函数
