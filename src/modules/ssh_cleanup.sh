#!/usr/bin/env bash

# ============================================================
# SH-AI SSH 清理业务模块
# ============================================================
# 职责: SSH 连接清理功能
# 需求: 3.5

# @cmd 清理失效的 SSH 连接和缓存。触发:用户说 'cleanup'
# @alias ssh.cleanup
ssh_cleanup() {
    _output_header 2 "清理陈旧连接"    
    _info "正在扫描和清理陈旧的 SSH 连接..."
    
    local cleaned_count=0
    local registry_file="$SSH_CONTROL_DIR/connection_registry"
    
    # 清理陈旧的套接字文件
    if [[ -d "$SSH_CONTROL_DIR" ]]; then
        for socket_file in "$SSH_CONTROL_DIR"/ssh-*; do
            [[ -e "$socket_file" ]] || continue
            if [[ -S "$socket_file" ]]; then
                # 从文件名提取连接ID
                local connection_id="${socket_file##*/ssh-}"
                local target=""
                
                # 从注册表获取目标信息
                if [[ -f "$registry_file" ]]; then
                    local line
                    line=$(grep "^$connection_id:" "$registry_file" 2>/dev/null)
                    if [[ -n "$line" ]]; then
                        local remaining="${line#*:}"
                        target="${remaining%:*}"
                    fi
                fi
                
                # 如果找到目标，检查连接健康状态
                if [[ -n "$target" ]]; then
                    if ! _check_connection_health "$target" 2>/dev/null; then
                        # 连接不健康，清理套接字
                        rm -f "$socket_file" 2>/dev/null && ((cleaned_count++))
                        _info "清理陈旧连接: $target"
                    fi
                else
                    # 注册表中没有对应条目，直接清理
                    rm -f "$socket_file" 2>/dev/null && ((cleaned_count++))
                    _info "清理未注册的套接字: $(basename "$socket_file")"
                fi
            fi
        done
    fi
    
    # 清理注册表中的无效条目
    if command -v _cleanup_stale_connections >/dev/null 2>&1; then
        _cleanup_stale_connections 2>/dev/null || true
    fi
    
    if [[ $cleaned_count -gt 0 ]]; then
        _success "清理完成，共清理 $cleaned_count 个陈旧连接"
    else
        _info "没有发现需要清理的陈旧连接"
    fi
    
    # 显示清理后的连接状态
    _output_separator
    ssh_list || true
    
    return 0
}

# 导出函数
