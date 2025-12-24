#!/usr/bin/env bash

# ============================================================
# SH-AI SSH 连接管理核心模块
# ============================================================
# 职责: SSH ControlMaster 连接复用和健康检查
# 需求: 2.1, 2.2, 2.3, 3.4

# SSH 配置常量
readonly SSH_CONTROL_DIR="${SSH_CONTROL_DIR:-$HOME/.ssh/sh-ai-sockets}"
readonly SSH_TIMEOUT="${SSH_TIMEOUT:-10}"
readonly SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-30}"
readonly SSH_CONTROL_PERSIST="${SSH_CONTROL_PERSIST:-600}"

# 确保 SSH 控制目录存在
_ensure_ssh_control_dir() {
    if [[ ! -d "$SSH_CONTROL_DIR" ]]; then
        mkdir -p "$SSH_CONTROL_DIR"
        chmod 700 "$SSH_CONTROL_DIR"
    fi
}

# 生成连接的 MD5 标识符
_generate_connection_id() {
    local target="$1"
    echo -n "$target" | md5sum | cut -d' ' -f1
}

# 获取控制套接字路径
_get_control_socket() {
    local target="$1"
    local connection_id
    connection_id=$(_generate_connection_id "$target")
    echo "$SSH_CONTROL_DIR/ssh-$connection_id"
}

# 解析 SSH 目标 (user@host[:port])
_parse_ssh_target() {
    local target="$1"
    local user host port
    
    # 基本格式验证
    if [[ ! "$target" =~ ^[^@]+@[^@:]+(:([0-9]+))?$ ]]; then
        _error "无效的 SSH 目标格式: $target (应为 user@host[:port])"
        return 1
    fi
    
    # 检查是否有多个@符号
    local at_count
    at_count=$(echo "$target" | tr -cd '@' | wc -c)
    if [[ $at_count -ne 1 ]]; then
        _error "无效的 SSH 目标格式: $target (只能包含一个@符号)"
        return 1
    fi
    
    # 分离用户和主机部分
    user="${target%%@*}"
    local host_part="${target#*@}"
    
    # 分离主机和端口
    if [[ "$host_part" == *:* ]]; then
        host="${host_part%:*}"
        port="${host_part##*:}"
        
        # 验证端口号
        if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ $port -lt 1 ]] || [[ $port -gt 65535 ]]; then
            _error "无效的端口号: $port (应为 1-65535)"
            return 1
        fi
    else
        host="$host_part"
        port="22"
    fi
    
    # 验证用户名和主机名不为空
    if [[ -z "$user" ]]; then
        _error "用户名不能为空"
        return 1
    fi
    
    if [[ -z "$host" ]]; then
        _error "主机名不能为空"
        return 1
    fi
    
    # 输出解析结果
    echo "user=$user"
    echo "host=$host"
    echo "port=$port"
    echo "target=$target"
}

# 检查连接健康状态
_check_connection_health() {
    local target="$1"
    local control_socket
    control_socket=$(_get_control_socket "$target")
    
    if [[ ! -S "$control_socket" ]]; then
        return 1
    fi
    
    # 使用 SSH 检查连接状态
    if ssh -o ControlPath="$control_socket" \
           -o ConnectTimeout="$SSH_TIMEOUT" \
           -O check "$target" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 快速连接健康检查 (性能优化版本)
_quick_connection_health_check() {
    local target="$1"
    local control_socket
    control_socket=$(_get_control_socket "$target")
    
    # 首先检查套接字文件是否存在
    if [[ ! -S "$control_socket" ]]; then
        return 1
    fi
    
    # 检查套接字文件的修改时间，如果太旧则认为可能已断开
    local socket_age
    socket_age=$(($(date +%s) - $(stat -c %Y "$control_socket" 2>/dev/null || echo 0)))
    
    # 如果套接字文件超过1小时未修改，进行完整检查
    if [[ $socket_age -gt 3600 ]]; then
        return $(_check_connection_health "$target")
    fi
    
    # 使用快速检查 (更短的超时时间)
    if ssh -o ControlPath="$control_socket" \
           -o ConnectTimeout="2" \
           -O check "$target" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 获取连接状态信息
_get_connection_status() {
    local target="$1"
    local control_socket
    control_socket=$(_get_control_socket "$target")
    
    local status="disconnected"
    local socket_exists="false"
    local health_check="false"
    local connection_time="unknown"
    
    # 检查套接字文件是否存在
    if [[ -S "$control_socket" ]]; then
        socket_exists="true"
        connection_time=$(stat -c %Y "$control_socket" 2>/dev/null || echo "unknown")
        
        # 使用快速健康检查（性能优化）
        if _quick_connection_health_check "$target"; then
            status="connected"
            health_check="true"
        else
            status="stale"
        fi
    fi
    
    # 输出状态信息
    echo "status=$status"
    echo "socket_exists=$socket_exists"
    echo "health_check=$health_check"
    echo "connection_time=$connection_time"
    echo "control_socket=$control_socket"
}

# 建立 SSH 连接
_establish_connection() {
    local target="$1"
    local control_socket
    control_socket=$(_get_control_socket "$target")
    
    _ensure_ssh_control_dir
    
    # 如果连接已存在且健康，直接返回
    if _check_connection_health "$target"; then
        _debug "连接已存在且健康: $target"
        return 0
    fi
    
    # 清理可能存在的陈旧套接字
    if [[ -S "$control_socket" ]]; then
        rm -f "$control_socket"
    fi
    
    _connect_info "正在建立连接: $target"
    
    # 解析目标以获取端口信息
    local target_info
    if ! target_info=$(_parse_ssh_target "$target"); then
        return 1
    fi
    
    local user host port
    eval "$target_info"
    
    # 建立 ControlMaster 连接
    if ssh -o ControlMaster=yes \
           -o ControlPath="$control_socket" \
           -o ControlPersist="$SSH_CONTROL_PERSIST" \
           -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o LogLevel=ERROR \
           -p "$port" \
           -N "$user@$host" &
    then
        # 等待连接建立
        local attempts=0
        local max_attempts=30  # 增加等待时间
        
        while [[ $attempts -lt $max_attempts ]]; do
            # 先检查套接字文件是否存在
            if [[ -S "$control_socket" ]]; then
                # 等待一下让连接稳定
                sleep 1
                # 再检查连接健康状态
                if _check_connection_health "$target"; then
                    # 注册连接信息
                    _register_connection "$target"
                    _success "连接建立成功: $target"
                    return 0
                fi
            fi
            
            sleep 1
            ((attempts++))
        done
        
        _error "连接建立超时: $target"
        return 1
    else
        _error "连接建立失败: $target"
        return 1
    fi
}

# 关闭 SSH 连接
_close_connection() {
    local target="$1"
    local control_socket
    control_socket=$(_get_control_socket "$target")
    
    if [[ ! -S "$control_socket" ]]; then
        _warning "连接不存在: $target"
        return 1
    fi
    
    _disconnect_info "正在关闭连接: $target"
    
    # 发送退出命令
    if ssh -o ControlPath="$control_socket" \
           -O exit "$target" &>/dev/null; then
        # 注销连接信息
        _unregister_connection "$target"
        _success "连接关闭成功: $target"
        return 0
    else
        # 强制删除套接字文件
        rm -f "$control_socket"
        # 注销连接信息
        _unregister_connection "$target"
        _warning "强制关闭连接: $target"
        return 0
    fi
}

# 执行远程命令
_execute_remote_command() {
    local target="$1"
    local command="$2"
    local control_socket
    control_socket=$(_get_control_socket "$target")
    
    if [[ ! -S "$control_socket" ]]; then
        _error "连接不存在: $target"
        return 1
    fi
    
    if ! _check_connection_health "$target"; then
        _error "连接不健康: $target"
        return 1
    fi
    
    # 执行远程命令
    ssh -o ControlPath="$control_socket" \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        -o LogLevel=ERROR \
        "$target" "$command"
}

# 连接注册表文件路径
_get_connection_registry_file() {
    echo "$SSH_CONTROL_DIR/connection_registry"
}

# 注册连接信息
_register_connection() {
    local target="$1"
    local connection_id
    connection_id=$(_generate_connection_id "$target")
    local registry_file
    registry_file=$(_get_connection_registry_file)
    
    _ensure_ssh_control_dir
    
    # 创建或更新注册表条目
    # 格式: connection_id:target:timestamp
    local timestamp
    timestamp=$(date +%s)
    local entry="$connection_id:$target:$timestamp"
    
    # 移除旧条目（如果存在）
    if [[ -f "$registry_file" ]]; then
        grep -v "^$connection_id:" "$registry_file" > "$registry_file.tmp" 2>/dev/null || true
        mv "$registry_file.tmp" "$registry_file"
    fi
    
    # 添加新条目
    echo "$entry" >> "$registry_file"
    
    _debug "连接已注册: $target -> $connection_id"
}

# 注销连接信息
_unregister_connection() {
    local target="$1"
    local connection_id
    connection_id=$(_generate_connection_id "$target")
    local registry_file
    registry_file=$(_get_connection_registry_file)
    
    if [[ -f "$registry_file" ]]; then
        grep -v "^$connection_id:" "$registry_file" > "$registry_file.tmp" 2>/dev/null || true
        mv "$registry_file.tmp" "$registry_file"
        _debug "连接已注销: $target -> $connection_id"
    fi
}

# 根据连接ID获取目标信息
_get_target_by_connection_id() {
    local connection_id="$1"
    local registry_file
    registry_file=$(_get_connection_registry_file)
    
    if [[ -f "$registry_file" ]]; then
        local entry
        entry=$(grep "^$connection_id:" "$registry_file" 2>/dev/null)
        if [[ -n "$entry" ]]; then
            echo "$entry" | cut -d':' -f2
            return 0
        fi
    fi
    
    return 1
}

# 获取连接的注册时间
_get_connection_register_time() {
    local connection_id="$1"
    local registry_file
    registry_file=$(_get_connection_registry_file)
    
    if [[ -f "$registry_file" ]]; then
        local entry
        entry=$(grep "^$connection_id:" "$registry_file" 2>/dev/null)
        if [[ -n "$entry" ]]; then
            echo "$entry" | cut -d':' -f3
            return 0
        fi
    fi
    
    return 1
}

# 列出所有活跃连接
_list_active_connections() {
    _ensure_ssh_control_dir
    
    local connections=()
    
    # 扫描控制套接字目录
    for socket_file in "$SSH_CONTROL_DIR"/ssh-*; do
        if [[ -S "$socket_file" ]]; then
            local connection_id="${socket_file##*/ssh-}"
            
            # 获取对应的目标信息
            local target
            if target=$(_get_target_by_connection_id "$connection_id"); then
                connections+=("$target")
            else
                # 如果注册表中没有记录，尝试清理陈旧套接字
                _debug "发现未注册的套接字: $socket_file"
                connections+=("unknown:$connection_id")
            fi
        fi
    done
    
    printf '%s\n' "${connections[@]}"
}

# 列出所有连接的详细信息
_list_connections_detailed() {
    _ensure_ssh_control_dir
    
    local registry_file
    registry_file=$(_get_connection_registry_file)
    
    # 如果注册表不存在，返回空
    if [[ ! -f "$registry_file" ]]; then
        return 0
    fi
    
    # 读取注册表并检查每个连接的状态
    while IFS=':' read -r connection_id target register_time; do
        if [[ -n "$connection_id" && -n "$target" ]]; then
            local control_socket
            control_socket=$(_get_control_socket "$target")
            
            local status="disconnected"
            local health="false"
            local device_type="unknown"
            
            # 检查套接字是否存在
            if [[ -S "$control_socket" ]]; then
                # 检查连接健康状态
                if _check_connection_health "$target"; then
                    status="connected"
                    health="true"
                else
                    status="stale"
                    health="false"
                fi
            fi
            
            # 获取设备类型
            device_type=$(_get_cached_device_type "$target" 2>/dev/null || echo "unknown")
            
            # 格式化注册时间
            local formatted_time="unknown"
            if [[ "$register_time" =~ ^[0-9]+$ ]]; then
                formatted_time=$(date -d "@$register_time" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
            fi
            
            # 输出连接信息
            echo "$target:$status:$health:$device_type:$formatted_time"
        fi
    done < "$registry_file"
}

# 清理陈旧连接和注册表 (性能优化版本)
_cleanup_stale_connections() {
    _ensure_ssh_control_dir
    
    local cleaned_sockets=0
    local cleaned_registry=0
    local registry_file
    registry_file=$(_get_connection_registry_file)
    
    # 批量收集套接字文件信息，减少文件系统调用
    local socket_files=()
    local connection_ids=()
    
    for socket_file in "$SSH_CONTROL_DIR"/ssh-*; do
        if [[ -S "$socket_file" ]]; then
            socket_files+=("$socket_file")
            connection_ids+=("${socket_file##*/ssh-}")
        fi
    done
    
    # 如果没有套接字文件，直接返回
    if [[ ${#socket_files[@]} -eq 0 ]]; then
        _debug "没有套接字文件需要清理"
        return 0
    fi
    
    # 批量处理套接字文件
    local i=0
    for socket_file in "${socket_files[@]}"; do
        local connection_id="${connection_ids[$i]}"
        local target
        
        # 获取对应的目标信息
        if target=$(_get_target_by_connection_id "$connection_id"); then
            # 使用快速健康检查
            if ! _quick_connection_health_check "$target"; then
                # 连接无效，清理套接字和注册表
                rm -f "$socket_file"
                _unregister_connection "$target"
                ((cleaned_sockets++))
                _debug "清理陈旧连接: $target"
            fi
        else
            # 没有注册信息的套接字，检查是否有进程使用
            if ! fuser "$socket_file" &>/dev/null 2>&1; then
                rm -f "$socket_file"
                ((cleaned_sockets++))
                _debug "清理未注册套接字: $socket_file"
            fi
        fi
        ((i++))
    done
    
    # 清理注册表中的无效条目
    if [[ -f "$registry_file" ]]; then
        local temp_registry="$registry_file.cleanup"
        
        while IFS=':' read -r connection_id target register_time; do
            if [[ -n "$connection_id" && -n "$target" ]]; then
                local control_socket
                control_socket=$(_get_control_socket "$target")
                
                # 如果套接字文件存在，保留注册表条目
                if [[ -S "$control_socket" ]]; then
                    echo "$connection_id:$target:$register_time" >> "$temp_registry"
                else
                    ((cleaned_registry++))
                    _debug "清理注册表条目: $target"
                fi
            fi
        done < "$registry_file"
        
        # 替换注册表文件
        if [[ -f "$temp_registry" ]]; then
            mv "$temp_registry" "$registry_file"
        else
            # 如果没有有效条目，删除注册表文件
            rm -f "$registry_file"
        fi
    fi
    
    # 报告清理结果
    local total_cleaned=$((cleaned_sockets + cleaned_registry))
    if [[ $total_cleaned -gt 0 ]]; then
        _info "清理完成: $cleaned_sockets 个套接字文件, $cleaned_registry 个注册表条目"
    else
        _debug "没有需要清理的陈旧连接"
    fi
    
    return 0
}

# 重新连接
_reconnect() {
    local target="$1"
    
    _info "重新连接: $target"
    
    # 先关闭现有连接
    _close_connection "$target"
    
    # 等待一秒
    sleep 1
    
    # 重新建立连接
    _establish_connection "$target"
}

# 连接池管理
_manage_connection_pool() {
    local max_connections="${SSH_MAX_CONNECTIONS:-10}"
    local registry_file
    registry_file=$(_get_connection_registry_file)
    
    if [[ ! -f "$registry_file" ]]; then
        return 0
    fi
    
    # 统计当前连接数
    local connection_count
    connection_count=$(wc -l < "$registry_file" 2>/dev/null || echo 0)
    
    # 如果连接数超过限制，清理最旧的连接
    if [[ $connection_count -gt $max_connections ]]; then
        _debug "连接数超过限制 ($connection_count > $max_connections)，清理最旧连接"
        
        # 按时间戳排序，删除最旧的连接
        local temp_file="$registry_file.tmp"
        sort -t: -k3 -n "$registry_file" | tail -n "$max_connections" > "$temp_file"
        mv "$temp_file" "$registry_file"
        
        # 清理对应的套接字文件
        _cleanup_stale_connections
    fi
}

# SSH 核心模块初始化 (性能优化版本)
_ssh_core_init() {
    _ensure_ssh_control_dir
    
    # 异步清理陈旧连接 (不阻塞主流程)
    (_cleanup_stale_connections &)
    
    # 管理连接池
    _manage_connection_pool
    
    _debug "SSH 核心模块初始化完成"
}

# 导出核心函数
export -f _ensure_ssh_control_dir _generate_connection_id _get_control_socket
export -f _parse_ssh_target _check_connection_health _get_connection_status
export -f _establish_connection _close_connection _execute_remote_command
export -f _list_active_connections _cleanup_stale_connections _reconnect
export -f _register_connection _unregister_connection _get_target_by_connection_id
export -f _get_connection_register_time _list_connections_detailed
export -f _quick_connection_health_check _manage_connection_pool
export -f _ssh_core_init