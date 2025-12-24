#!/usr/bin/env bash

# ============================================================
# SH-AI SSH 连接列表业务模块
# ============================================================
# 职责: 显示系统可用的 SSH 配置
# 需求: 3.1, 3.2

# @cmd 列出所有 SSH 连接及其状态。触发:用户说 'list' 
# @alias ssh.list
ssh_list() {
    _output_header 2 "SSH 连接列表"    
    # 显示表格头
    _output ""
    _output "| 主机名 | 地址 | 端口 | 用户 | 连接状态 | 设备类型 |"
    _output "|--------|------|------|------|----------|----------|"
    
    # 初始化计数器
    local total_hosts=0
    local has_hosts=false
    
    # 声明全局计数器（在子函数中使用）
    connected_hosts=0
    
    # 声明变量
    local host hostname user port current_host current_hostname current_user current_port
    local connection_status device_type status_icon
    
    # 初始化当前主机变量
    current_host=""
    current_hostname=""
    current_user=""
    current_port="22"
    
    # 读取 SSH 配置文件
    local ssh_config="$HOME/.ssh/config"
    
    if [[ -f "$ssh_config" ]]; then
        # 解析 SSH 配置文件
        while read -r line; do
            # 跳过注释和空行
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            # 处理 Host 行
            if [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+ ]]; then
                # 如果之前有主机配置，先处理它
                if [[ -n "$current_host" ]]; then
                    _process_ssh_host "$current_host" "$current_hostname" "$current_user" "$current_port"
                    ((++total_hosts))
                    has_hosts=true
                fi
                
                # 开始新的主机配置
                current_host=$(echo "$line" | sed 's/^[[:space:]]*Host[[:space:]]*//' | awk '{print $1}')
                current_hostname=""
                current_user=""
                current_port="22"
                
                # 跳过通配符主机
                [[ "$current_host" =~ \* ]] && current_host=""
                continue
            fi
            
            # 只有在有效主机配置下才处理其他选项
            [[ -z "$current_host" ]] && continue
            
            # 处理 HostName
            if [[ "$line" =~ ^[[:space:]]*HostName[[:space:]]+ ]]; then
                current_hostname=$(echo "$line" | sed 's/^[[:space:]]*HostName[[:space:]]*//')
            fi
            
            # 处理 User
            if [[ "$line" =~ ^[[:space:]]*User[[:space:]]+ ]]; then
                current_user=$(echo "$line" | sed 's/^[[:space:]]*User[[:space:]]*//')
            fi
            
            # 处理 Port
            if [[ "$line" =~ ^[[:space:]]*Port[[:space:]]+ ]]; then
                current_port=$(echo "$line" | sed 's/^[[:space:]]*Port[[:space:]]*//')
            fi
            
        done < "$ssh_config"
        
        # 处理最后一个主机配置
        if [[ -n "$current_host" ]]; then
            _process_ssh_host "$current_host" "$current_hostname" "$current_user" "$current_port"
            ((++total_hosts))
            has_hosts=true
        fi
    fi
    
    # 如果没有找到主机配置
    if [[ "$has_hosts" != "true" ]]; then
        _output ""
        _info "未找到 SSH 主机配置"
        
        if [[ ! -f "$ssh_config" ]]; then
            _info "SSH 配置文件不存在: $ssh_config"
            _info "可以创建配置文件来管理 SSH 连接"
        else
            _info "SSH 配置文件为空或没有有效的主机配置"
        fi
        
        _output ""
        _output "配置示例"
        _output ""
        _output "Host myserver"
        _output "    HostName 192.168.1.100"
        _output "    User root"
        _output "    Port 22"
    else
        _output ""
        
        # 显示统计信息
        _output_header 3 "连接统计"        _output ""
        _output "| 项目 | 值 |"
        _output "|------|-----|"
        _output "| 配置主机数 | $total_hosts |"
        _output "| 活跃连接数 | $connected_hosts |"
        _output "| 可用连接数 | $((total_hosts - connected_hosts)) |"
    fi
    
    # 显示系统SSH信息
    _output_separator
    _output_header 3 "系统SSH信息"    _output ""
    _output "| 项目 | 值 |"
    _output "|------|-----|"
    
    # SSH客户端版本
    local ssh_version
    ssh_version=$(ssh -V 2>&1 | head -n1 | cut -d' ' -f1 2>/dev/null || echo "未知")
    _output "| SSH版本 | $ssh_version |"
    
    # SSH配置文件
    if [[ -f "$ssh_config" ]]; then
        _output "| 配置文件 | ~/.ssh/config (存在) |"
    else
        _output "| 配置文件 | ~/.ssh/config (不存在) |"
    fi
    
    # 已知主机数量
    local known_hosts_count=0
    if [[ -f "$HOME/.ssh/known_hosts" ]]; then
        known_hosts_count=$(wc -l < "$HOME/.ssh/known_hosts" 2>/dev/null || echo "0")
    fi
    _output "| 已知主机 | $known_hosts_count |"
    
    # SSH控制目录
    _output "| 控制目录 | ${SSH_CONTROL_DIR:-未设置} |"
    
    _output ""
    
    # 使用提示
    _info "使用 /connect <主机名> 建立连接"
    _info "使用 /status <目标> 查看连接状态"
    _info "使用 /cleanup 清理陈旧连接"
    
    return 0
}

# 处理单个 SSH 主机配置
_process_ssh_host() {
    local host="$1"
    local hostname="$2"
    local user="$3"
    local port="$4"
    
    # 设置默认值
    [[ -z "$hostname" ]] && hostname="$host"
    [[ -z "$user" ]] && user="$(whoami)"
    [[ -z "$port" ]] && port="22"
    
    # 构建目标字符串用于检查连接状态
    local target="$user@$hostname"
    [[ "$port" != "22" ]] && target="$target:$port"
    
    # 检查连接状态
    local connection_status="未连接"
    local status_icon=""
    local device_type="未知"
    
    # 检查是否有活跃连接
    if command -v _check_connection_health >/dev/null 2>&1; then
        if _check_connection_health "$target" 2>/dev/null; then
            connection_status="已连接"
            status_icon=""
            ((++connected_hosts))
            
            # 获取设备类型
            if device_type=$(_get_cached_device_type "$target" 2>/dev/null); then
                [[ -n "$device_type" ]] || device_type="未知"
            fi
        fi
    fi
    
    # 输出表格行
    _output "| $host | $hostname | $port | $user | $status_icon $connection_status | $device_type |"
}

# 导出函数
export -f ssh_list _process_ssh_host
