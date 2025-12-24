#!/usr/bin/env bash

# ============================================================
# SH-AI AI 命令生成核心模块
# ============================================================
# 职责: 基于意图和设备类型的智能命令生成（通用工具函数）
# 使用: 主要被 ssh_analy.sh 使用，ssh_ai.sh 有自己的纯 AI 实现
# 需求: 6.1, 6.2, 6.3, 6.5, 6.6, 7.1, 7.2, 7.3, 7.4, 7.5

# AI_MAIN_SESSION constant removed - session management handled by agent framework

# Note: request_ai_processing() is now implemented in ai_request.sh core module
# This module uses that implementation for AI processing

# 危险命令模式列表
readonly DANGEROUS_COMMANDS=(
    "rm"
    "reboot"
    "shutdown"
    "halt"
    "dd"
    "mkfs"
    "fdisk"
    "parted"
    "format"
    "del"
    "erase"
    "factory-reset"
    "reset"
    "reload"
    "restart"
)

# 检测危险命令
_is_dangerous_command() {
    local command="$1"
    
    # 清理命令，移除前缀和空格
    command=$(echo "$command" | sed 's/^[[:space:]]*//' | sed 's/^bash:[[:space:]]*//' | sed 's/^sh:[[:space:]]*//')
    
    # 提取命令的第一个词
    local first_word
    first_word=$(echo "$command" | awk '{print $1}')
    
    # 检查是否为危险命令
    for dangerous_cmd in "${DANGEROUS_COMMANDS[@]}"; do
        if [[ "$first_word" == "$dangerous_cmd" ]] || [[ "$first_word" == *"$dangerous_cmd"* ]]; then
            return 0  # 是危险命令
        fi
    done
    
    # 检查特殊危险模式
    if [[ "$command" =~ (rm[[:space:]]+-.*r|rm[[:space:]]+-.*f|>/dev/|format[[:space:]]+|del[[:space:]]+.*\*) ]]; then
        return 0  # 是危险命令
    fi
    
    return 1  # 不是危险命令
}

# 清理 AI 输出，提取纯命令
# 需求: 2.1, 2.2, 2.3, 2.5
_clean_command_output() {
    local ai_output="$1"
    
    # Debug output (requirement 5.5)
    if [[ "${DEBUG:-0}" == "1" ]]; then
        _debug "清理阶段: 开始"
        _debug "原始输入长度: ${#ai_output} 字符"
    fi
    
    # Step 1: Remove markdown code blocks
    ai_output=$(echo "$ai_output" | sed '/^```/d')
    
    # Debug output (requirement 5.5)
    if [[ "${DEBUG:-0}" == "1" ]]; then
        _debug "步骤 1: 移除 markdown 代码块"
        _debug "处理后长度: ${#ai_output} 字符"
    fi
    
    # Step 2: Remove command prefixes (bash:, sh:, $, #)
    ai_output=$(echo "$ai_output" | sed 's/^bash:[[:space:]]*//' | sed 's/^sh:[[:space:]]*//')
    ai_output=$(echo "$ai_output" | sed 's/^[$#][[:space:]]*//')
    
    # Debug output (requirement 5.5)
    if [[ "${DEBUG:-0}" == "1" ]]; then
        _debug "步骤 2: 移除命令前缀"
        _debug "处理后长度: ${#ai_output} 字符"
    fi
    
    # Step 3: Trim whitespace
    ai_output=$(echo "$ai_output" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    # Debug output (requirement 5.5)
    if [[ "${DEBUG:-0}" == "1" ]]; then
        _debug "步骤 3: 修剪空白字符"
        _debug "处理后长度: ${#ai_output} 字符"
    fi
    
    # Step 4: Extract first valid command line only (conservative approach)
    local first_command=""
    local line_count=0
    while IFS= read -r line; do
        ((line_count++))
        
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Skip obvious explanation lines (but be conservative)
        # Only skip lines that clearly start with explanatory phrases
        if [[ "$line" =~ ^(这是|This is|The following|以下是|下面是) ]]; then
            # Debug output (requirement 5.5)
            if [[ "${DEBUG:-0}" == "1" ]]; then
                _debug "跳过解释行 #$line_count: $line"
            fi
            continue
        fi
        
        # Remove $ or # prompt if present at start of line
        line=$(echo "$line" | sed 's/^[$#][[:space:]]*//')
        
        # Trim whitespace again after removing prompt
        line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        
        # Take first line that looks like a command
        # Commands typically start with alphanumeric, underscore, slash, dot, or dash
        if [[ "$line" =~ ^[a-zA-Z0-9_/.-] ]]; then
            first_command="$line"
            
            # Debug output (requirement 5.5)
            if [[ "${DEBUG:-0}" == "1" ]]; then
                _debug "找到有效命令行 #$line_count: $line"
            fi
            break
        fi
    done <<< "$ai_output"
    
    # Debug output (requirement 5.5)
    if [[ "${DEBUG:-0}" == "1" ]]; then
        _debug "步骤 4: 提取第一个有效命令行"
        if [[ -n "$first_command" ]]; then
            _debug "清理阶段: 成功"
            _debug "最终命令: $first_command"
        else
            _debug "清理阶段: 失败 - 未找到有效命令"
        fi
    fi
    
    # Return empty string if no valid command found (requirement 2.5)
    echo "$first_command"
}

# 验证生成的命令
# 需求: 3.1, 3.2, 3.3, 3.5
_validate_generated_command() {
    local command="$1"
    
    # Debug output (requirement 5.5)
    if [[ "${DEBUG:-0}" == "1" ]]; then
        _debug "验证阶段: 开始"
        _debug "待验证命令: $command"
    fi
    
    # Check 1: Not empty (requirement 3.1, 5.3)
    if [[ -z "$command" ]]; then
        _error "命令验证失败: 生成的命令为空"
        _error "验证规则: 命令不能为空字符串"
        _error "建议: 检查 AI 响应是否包含有效命令"
        
        # Debug output (requirement 5.5)
        if [[ "${DEBUG:-0}" == "1" ]]; then
            _debug "验证失败: 空命令"
        fi
        return 1
    fi
    
    # Check 2: Not only whitespace (requirement 3.2, 5.3)
    if [[ ! "$command" =~ [^[:space:]] ]]; then
        _error "命令验证失败: 命令只包含空白字符"
        _error "验证规则: 命令必须包含至少一个非空白字符"
        _error "命令内容: '$command'"
        _error "建议: 检查命令清理逻辑是否正确"
        
        # Debug output (requirement 5.5)
        if [[ "${DEBUG:-0}" == "1" ]]; then
            _debug "验证失败: 仅包含空白字符"
        fi
        return 1
    fi
    
    # Check 3: Reasonable length (requirement 5.3)
    if [[ ${#command} -gt 1000 ]]; then
        _error "命令验证失败: 生成的命令过长"
        _error "验证规则: 命令长度不能超过 1000 字符"
        _error "实际长度: ${#command} 字符"
        _error "命令前 100 字符: ${command:0:100}..."
        _error "建议: 检查 AI 是否返回了多个命令或包含过多解释文本"
        
        # Debug output (requirement 5.5)
        if [[ "${DEBUG:-0}" == "1" ]]; then
            _debug "验证失败: 命令过长 (${#command} 字符)"
        fi
        return 1
    fi
    
    # Check 4: Contains executable content format (requirement 3.1, 5.3)
    # Commands should start with alphanumeric, underscore, slash, dot, or dash
    if [[ ! "$command" =~ ^[a-zA-Z0-9_/.-] ]]; then
        _error "命令验证失败: 命令格式无效"
        _error "验证规则: 命令必须以字母、数字、下划线、斜杠、点或破折号开头"
        _error "实际开头字符: '${command:0:1}'"
        _error "命令内容: $command"
        _error "建议: 检查命令清理是否移除了所有前缀和格式字符"
        
        # Debug output (requirement 5.5)
        if [[ "${DEBUG:-0}" == "1" ]]; then
            _debug "验证失败: 无效的开头字符"
        fi
        return 1
    fi
    
    # Check 5: Dangerous command check (requirement 3.3, 5.3)
    if _is_dangerous_command "$command"; then
        _error "命令验证失败: 检测到危险命令"
        _error "验证规则: 禁止执行可能造成系统损坏的危险命令"
        _error "危险命令列表: ${DANGEROUS_COMMANDS[*]}"
        _error "检测到的命令: $command"
        _error "建议: 如需执行危险操作，请使用 /exec 命令手动执行"
        
        # Debug output (requirement 5.5)
        if [[ "${DEBUG:-0}" == "1" ]]; then
            _debug "验证失败: 危险命令"
        fi
        return 1
    fi
    
    # Check 6: Shell injection patterns (requirement 3.3)
    # Note: Some special characters are legitimate in commands, so we only warn
    if [[ "$command" =~ [\;\|\&\`\$\(\)] ]]; then
        _debug "命令包含特殊字符，已通过基本验证: $command"
        
        # Debug output (requirement 5.5)
        if [[ "${DEBUG:-0}" == "1" ]]; then
            _debug "警告: 命令包含特殊字符（管道、重定向等）"
        fi
    fi
    
    # Debug output (requirement 5.5)
    if [[ "${DEBUG:-0}" == "1" ]]; then
        _debug "验证阶段: 成功"
        _debug "所有验证规则已通过"
    fi
    
    return 0
}

# 生成设备特定的 AI 提示（支持任意设备类型）
_generate_device_prompt() {
    local intent="$1"
    local device_type="$2"
    local target="$3"
    
    local device_context=""
    
    # 根据设备类型生成上下文提示
    # 支持常见类型的详细提示，其他类型使用通用提示
    case "$device_type" in
        linux|ubuntu|debian|fedora|centos|rhel|arch|alpine|*linux*)
            device_context="这是一个 Linux 系统（$device_type）。使用标准的 Linux 命令，如 ps, top, df, free, netstat, systemctl 等。根据具体发行版选择合适的包管理器（apt/yum/dnf/pacman）。"
            ;;
        openwrt|lede|*wrt*)
            device_context="这是一个 OpenWrt 路由器系统（$device_type）。使用 OpenWrt 特有的命令，如 uci, opkg, logread, wifi 等。避免使用 systemctl。"
            ;;
        cisco|*ios*|nx-os)
            device_context="这是一个 Cisco 网络设备（$device_type）。使用 Cisco IOS 命令，如 show running-config, show ip route, show interface 等。"
            ;;
        huawei|*vrp*)
            device_context="这是一个华为网络设备（$device_type）。使用华为 VRP 命令，如 display current-configuration, display ip routing-table 等。"
            ;;
        h3c|*comware*)
            device_context="这是一个 H3C 网络设备（$device_type）。使用 H3C Comware 命令，如 display current-configuration, display ip routing-table 等。"
            ;;
        freebsd|openbsd|netbsd|*bsd*)
            device_context="这是一个 BSD 系统（$device_type）。使用 BSD 特有的命令，如 sockstat, pstat, service 等。"
            ;;
        macos|darwin|*mac*)
            device_context="这是一个 macOS 系统（$device_type）。使用 macOS 特有的命令，如 launchctl, diskutil, system_profiler 等。"
            ;;
        windows|*win*)
            device_context="这是一个 Windows 系统（$device_type）。使用 Windows 命令，如 ipconfig, netstat, tasklist, systeminfo 等。"
            ;;
        juniper|*junos*)
            device_context="这是一个 Juniper 网络设备（$device_type）。使用 Junos 命令，如 show configuration, show route 等。"
            ;;
        arista|*eos*)
            device_context="这是一个 Arista 网络设备（$device_type）。使用 EOS 命令，如 show running-config, show ip route 等。"
            ;;
        mikrotik|routeros|*mikrotik*)
            device_context="这是一个 MikroTik 设备（$device_type）。使用 RouterOS 命令。"
            ;;
        fortinet|fortios|*forti*)
            device_context="这是一个 Fortinet 防火墙（$device_type）。使用 FortiOS 命令，如 get system status, show firewall policy 等。"
            ;;
        paloalto|pan-os|*palo*)
            device_context="这是一个 Palo Alto 防火墙（$device_type）。使用 PAN-OS 命令。"
            ;;
        *)
            # 通用提示：让 AI 根据设备类型名称推断
            device_context="这是一个 $device_type 设备。请根据设备类型名称推断合适的命令语法和工具。如果是 Linux 发行版，使用相应的包管理器和系统工具。如果是网络设备，使用相应厂商的命令语法。"
            ;;
    esac
    
    local prompt="你是一个专业的系统管理员助手。根据用户意图和设备类型，生成准确的命令。

设备信息：
- 目标: $target
- 设备类型: $device_type
- 设备说明: $device_context

用户意图: $intent

要求：
1. 只返回可执行的命令，不要解释
2. 命令必须适合 $device_type 设备
3. 根据设备类型的具体信息（如版本号）选择合适的命令
4. 避免危险操作（删除、重启、格式化等）
5. 如果需要多个命令，用 && 连接
6. 不要使用 Markdown 格式
7. 不要添加 $ 或 # 提示符

请直接返回命令："
    
    echo "$prompt"
}


# 基于规则的结果分析
_analyze_command_result_by_rules() {
    local intent="$1"
    local target="$2"
    local command="$3"
    local result="$4"
    local device_type="${5:-unknown}"
    
    _analyze_info "正在分析执行结果"
    _output_header 3 "命令结果分析"
    
    case "$intent" in
        *"防火墙"*|*"firewall"*)
            _info "防火墙分析结果:"
            if echo "$result" | grep -q "ACCEPT"; then
                _success "发现允许规则"
            fi
            if echo "$result" | grep -q "DROP\|REJECT"; then
                _warning "发现拒绝规则"
            fi
            local rule_count=$(echo "$result" | grep -c "config\|Chain\|-A")
            _info "规则数量: $rule_count"
            ;;
        *"网络"*|*"network"*|*"接口"*)
            _info "网络接口分析:"
            local interface_count=$(echo "$result" | grep -c "inet addr\|inet ")
            _info "活动接口数: $interface_count"
            if echo "$result" | grep -q "UP.*RUNNING"; then
                _success "发现活动接口"
            fi
            ;;
        *"状态"*|*"status"*)
            _info "系统状态分析:"
            if echo "$result" | grep -q "load average"; then
                local load=$(echo "$result" | grep "load average" | awk '{print $10}' | head -1)
                _info "系统负载: ${load:-未知}"
            fi
            if echo "$result" | grep -q "up.*day"; then
                _success "系统运行稳定"
            fi
            ;;
        *)
            _info "通用结果分析:"
            local line_count=$(echo "$result" | wc -l)
            local size=$(echo "$result" | wc -c)
            _info "输出行数: $line_count"
            _info "输出大小: $size 字节"
            ;;
    esac
    
    _info "执行意图: $intent"
    _info "目标设备: $target ($device_type)"
    _info "执行命令: $command"
    
    return 0
}

# 基于规则的命令生成（作为 AI 的后备方案，支持任意设备类型）
_generate_command_by_rules() {
    local intent="$1"
    local device_type="$2"
    
    local generated_command=""
    
    # 根据设备类型模式匹配，支持更灵活的类型识别
    local is_linux=false
    local is_openwrt=false
    local is_cisco=false
    local is_huawei=false
    local is_bsd=false
    local is_network_device=false
    
    # 识别设备类型类别
    case "$device_type" in
        linux|ubuntu|debian|fedora|centos|rhel|arch|alpine|*linux*)
            is_linux=true
            ;;
        openwrt|lede|*wrt*)
            is_openwrt=true
            ;;
        cisco|*ios*|nx-os)
            is_cisco=true
            is_network_device=true
            ;;
        huawei|*vrp*|h3c|*comware*)
            is_huawei=true
            is_network_device=true
            ;;
        freebsd|openbsd|netbsd|*bsd*)
            is_bsd=true
            ;;
        juniper|arista|mikrotik|fortinet|paloalto|*junos*|*eos*|*forti*|*palo*)
            is_network_device=true
            ;;
    esac
    
    # 基于意图和设备类型生成命令
    case "$intent" in
        *"防火墙"*|*"firewall"*)
            if [[ "$is_openwrt" == true ]]; then
                generated_command="uci show firewall"
            elif [[ "$is_linux" == true ]]; then
                generated_command="iptables -L -n -v"
            elif [[ "$is_cisco" == true ]]; then
                generated_command="show access-lists"
            elif [[ "$is_network_device" == true ]]; then
                generated_command="show firewall policy"
            else
                generated_command="iptables -L"
            fi
            ;;
        *"网络"*|*"network"*|*"接口"*|*"interface"*)
            if [[ "$is_cisco" == true ]]; then
                generated_command="show ip interface brief"
            elif [[ "$is_huawei" == true ]]; then
                generated_command="display ip interface brief"
            elif [[ "$is_openwrt" == true ]]; then
                generated_command="uci show network && ifconfig"
            elif [[ "$is_network_device" == true ]]; then
                generated_command="show interface"
            else
                generated_command="ip addr show"
            fi
            ;;
        *"状态"*|*"status"*|*"信息"*|*"info"*)
            if [[ "$is_openwrt" == true ]]; then
                generated_command="uname -a && uptime && free"
            elif [[ "$is_cisco" == true ]] || [[ "$is_network_device" == true ]]; then
                generated_command="show version"
            else
                generated_command="uname -a && uptime && free -h"
            fi
            ;;
        *"配置"*|*"config"*)
            if [[ "$is_openwrt" == true ]]; then
                generated_command="uci show"
            elif [[ "$is_cisco" == true ]] || [[ "$is_network_device" == true ]]; then
                generated_command="show running-config"
            else
                generated_command="cat /etc/os-release"
            fi
            ;;
        *"路由"*|*"route"*)
            if [[ "$is_cisco" == true ]]; then
                generated_command="show ip route"
            elif [[ "$is_huawei" == true ]]; then
                generated_command="display ip routing-table"
            elif [[ "$is_network_device" == true ]]; then
                generated_command="show route"
            else
                generated_command="ip route show"
            fi
            ;;
        *"进程"*|*"process"*)
            if [[ "$is_network_device" == true ]]; then
                generated_command="show processes"
            else
                generated_command="ps aux | head -20"
            fi
            ;;
        *"内存"*|*"memory"*)
            if [[ "$is_network_device" == true ]]; then
                generated_command="show memory"
            elif [[ "$is_openwrt" == true ]]; then
                generated_command="cat /proc/meminfo"
            else
                generated_command="free -h"
            fi
            ;;
        *"日志"*|*"log"*|*"错误"*|*"error"*)
            if [[ "$is_openwrt" == true ]]; then
                generated_command="logread | tail -100"
            elif [[ "$is_network_device" == true ]]; then
                generated_command="show logging"
            else
                generated_command="journalctl -n 100 --no-pager || tail -100 /var/log/syslog || tail -100 /var/log/messages"
            fi
            ;;
        *)
            # 没有匹配的规则，返回空让 AI 生成
            generated_command=""
            ;;
    esac
    
    echo "$generated_command"
}

# 导出核心函数
export -f _is_dangerous_command _clean_command_output _validate_generated_command
export -f _generate_command_by_rules _analyze_command_result_by_rules
# Note: request_ai_processing is exported from ai_request.sh module