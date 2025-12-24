#!/usr/bin/env bash

# ============================================================
# SH-AI 设备检测核心模块
# ============================================================
# 职责: 设备类型检测和管理
# 需求: 4.1, 4.2, 4.3, 4.4, 4.5

# 常见的设备类型（用于提示和参考，不用于严格验证）
readonly COMMON_DEVICE_TYPES=(
    "linux"
    "ubuntu"
    "debian"
    "fedora"
    "centos"
    "rhel"
    "arch"
    "alpine"
    "openwrt"
    "cisco"
    "huawei"
    "h3c"
    "freebsd"
    "macos"
    "windows"
    "juniper"
    "arista"
    "mikrotik"
    "fortinet"
    "paloalto"
    "unknown"
)

# 规范化设备类型名称（仅清理格式，不强制映射）
_normalize_device_type() {
    local device_type="$1"
    
    # 转换为小写并去除空白
    device_type=$(echo -n "$device_type" | tr '[:upper:]' '[:lower:]' | tr -d '\r\n' | sed -e 's/^ *//' -e 's/ *$//')
    
    # 处理特殊情况
    case "$device_type" in
        "")
            echo "unknown"
            return 0
            ;;
        "null")
            echo "unknown"
            return 0
            ;;
        *)
            # 返回规范化后的名称（保留原始类型信息）
            echo "$device_type"
            return 0
            ;;
    esac
}

# 验证设备类型（宽松验证：只要不为空且格式合理即可）
_validate_device_type() {
    local device_type="$1"
    
    # 规范化
    local normalized
    normalized=$(_normalize_device_type "$device_type")
    
    # 基本验证：不为空，不包含特殊字符
    if [[ -z "$normalized" ]]; then
        return 1
    fi
    
    # 检查是否包含危险字符（防止注入）
    if [[ "$normalized" =~ [^a-z0-9._-] ]]; then
        return 1
    fi
    
    # 长度检查（1-50字符）
    if [[ ${#normalized} -lt 1 || ${#normalized} -gt 50 ]]; then
        return 1
    fi
    
    return 0
}

# 注意：_get_cached_device_type 函数已在 cache.sh 中定义，这里不需要重复定义

# 缓存设备类型
_cache_device_type() {
    local target="$1"
    local device_type="$2"
    
    # 直接使用缓存模块的函数
    _save_device_cache "$target" "$device_type" "ai"
}

# 基于系统信息检测设备类型
_detect_device_type_basic() {
    local target="$1"
    
    # 检查连接是否可用
    if ! _check_connection_health "$target"; then
        _debug "连接不可用，无法检测设备类型: $target"
        return 1
    fi
    
    # 获取系统信息
    local uname_output
    if uname_output=$(_execute_remote_command "$target" "uname -a" 2>/dev/null); then
        case "$uname_output" in
            *Linux*)
                # 进一步检测Linux发行版，尝试解析 /etc/os-release 的 ID/NAME 并映射为规范类型
                local os_release
                if os_release=$(_execute_remote_command "$target" "cat /etc/os-release 2>/dev/null || cat /etc/openwrt_release 2>/dev/null"); then
                    # 优先检测 openwrt 标识
                    if echo "$os_release" | grep -qi "openwrt"; then
                        echo "openwrt"
                        return 0
                    fi

                    # 尝试从 ID 或 NAME 提取设备类型
                    local id_line name_line id_val name_val
                    id_line=$(echo "$os_release" | awk -F= '/^ID=/{print $2; exit}')
                    name_line=$(echo "$os_release" | awk -F= '/^NAME=/{print $2; exit}')
                    id_val=$(echo -n "$id_line" | tr -d '"' | tr '[:upper:]' '[:lower:]')
                    name_val=$(echo -n "$name_line" | tr -d '"' | tr '[:upper:]' '[:lower:]')
                    
                    # 优先使用 ID，然后尝试 NAME
                    if [[ -n "$id_val" ]] && _validate_device_type "$id_val"; then
                        echo "$id_val"
                        return 0
                    fi
                    if [[ -n "$name_val" ]] && _validate_device_type "$name_val"; then
                        echo "$name_val"
                        return 0
                    fi
                fi
                # fallback: treat as generic linux
                echo "linux"
                return 0
                ;;
            *FreeBSD*)
                echo "freebsd"
                return 0
                ;;
            *Darwin*)
                echo "macos"
                return 0
                ;;
            *CYGWIN*|*MINGW*|*MSYS*)
                echo "windows"
                return 0
                ;;
        esac
    fi
    
    # 尝试检测网络设备
    local hostname_output
    if hostname_output=$(_execute_remote_command "$target" "hostname" 2>/dev/null); then
        # 基于主机名模式检测
        case "$hostname_output" in
            *cisco*|*Cisco*)
                echo "cisco"
                return 0
                ;;
            *huawei*|*Huawei*)
                echo "huawei"
                return 0
                ;;
            *h3c*|*H3C*)
                echo "h3c"
                return 0
                ;;
        esac
    fi
    
    # 尝试检测特定命令
    if _execute_remote_command "$target" "show version" >/dev/null 2>&1; then
        # 可能是网络设备
        local show_version
        if show_version=$(_execute_remote_command "$target" "show version" 2>/dev/null); then
            case "$show_version" in
                *Cisco*)
                    echo "cisco"
                    return 0
                    ;;
                *Huawei*)
                    echo "huawei"
                    return 0
                    ;;
                *H3C*)
                    echo "h3c"
                    return 0
                    ;;
                *Juniper*)
                    echo "juniper"
                    return 0
                    ;;
                *Arista*)
                    echo "arista"
                    return 0
                    ;;
            esac
        fi
    fi
    
    # 默认返回unknown
    echo "unknown"
    return 0
}

# AI增强的设备类型检测
_detect_device_type_ai() {
    local target="$1"
    local force="${2:-false}"
    
    # 检查缓存
    if [[ "$force" != "true" ]]; then
        local cached_type
        if cached_type=$(_get_cached_device_type "$target"); then
            _debug "使用缓存的设备类型: $cached_type"
            echo "$cached_type"
            return 0
        fi
    fi
    
    # 基础检测
    local basic_type
    if basic_type=$(_detect_device_type_basic "$target"); then
        if [[ "$basic_type" != "unknown" ]]; then
            # 缓存结果
            _cache_device_type "$target" "$basic_type"
            echo "$basic_type"
            return 0
        fi
    fi
    
    # 如果基础检测失败，尝试AI检测
    if command -v aichat >/dev/null 2>&1; then
        _debug "尝试AI增强检测..."
        
        # 收集系统信息
        local system_info=""
        local commands=(
            "uname -a"
            "cat /etc/os-release"
            "cat /proc/version"
            "hostname"
            "whoami"
            "pwd"
            "ls -la /"
        )
        
        for cmd in "${commands[@]}"; do
            local output
            if output=$(_execute_remote_command "$target" "$cmd" 2>/dev/null); then
                system_info+="Command: $cmd\nOutput: $output\n\n"
            fi
        done
        
        if [[ -n "$system_info" ]]; then
            # 构建AI提示
            local ai_prompt="Based on the following system information, determine the device type. 
Respond with only one of these types: linux, openwrt, cisco, huawei, h3c, freebsd, macos, windows, juniper, arista, mikrotik, fortinet, paloalto, unknown

System Information:
$system_info

Device Type:"
            
            local ai_result
            if ai_result=$(echo "$ai_prompt" | aichat --no-stream 2>/dev/null | tail -n1 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]'); then
                # normalize AI output then validate/map
                local normalized
                normalized=$(_normalize_device_type "$ai_result")
                if _validate_device_type "$normalized"; then
                    _cache_device_type "$target" "$normalized"
                    echo "$normalized"
                    return 0
                fi
            fi
        fi
    fi
    
    # 如果所有方法都失败，返回需要手动输入
    echo "MANUAL_INPUT_REQUIRED"
    return 1
}

# 手动设置设备类型
_set_device_type_manual() {
    local target="$1"
    local device_type="$2"
    
    # 规范化设备类型（清理格式，保留原始信息）
    local normalized
    normalized=$(_normalize_device_type "$device_type")
    
    # 宽松验证（只检查格式安全性）
    if ! _validate_device_type "$normalized"; then
        _error "无效的设备类型格式: $device_type"
        _info "设备类型应为字母、数字、点、下划线或连字符的组合（1-50字符）"
        _info "示例: fedora, ubuntu-22.04, centos7, cisco-ios, huawei-vrp"
        return 1
    fi
    
    # 缓存规范化后的设备类型
    _cache_device_type "$target" "$normalized"
    
    # 返回规范化后的类型
    echo "$normalized"
    return 0
}

# 显示常见的设备类型（作为参考）
_show_common_device_types() {
    _output_header 3 "常见设备类型参考"
    _info "系统支持任意设备类型，AI 会根据具体类型生成相应命令"
    _output ""
    _output "常见类型示例："
    _output ""
    _output "| 类别 | 示例 |"
    _output "|------|------|"
    _output "| Linux 发行版 | fedora, ubuntu, debian, centos, rhel, arch, alpine |"
    _output "| 嵌入式 Linux | openwrt, lede |"
    _output "| BSD 系统 | freebsd, openbsd, netbsd |"
    _output "| 其他操作系统 | macos, windows |"
    _output "| 网络设备 | cisco, huawei, h3c, juniper, arista, mikrotik |"
    _output "| 防火墙 | fortinet, paloalto |"
    _output ""
    _info "你也可以使用更具体的版本信息，如: ubuntu-22.04, fedora-40, centos7"
}

# 导出函数
# 注意：_get_cached_device_type 在 cache.sh 中定义和导出，这里不需要重复导出
export -f _normalize_device_type _validate_device_type _cache_device_type
export -f _detect_device_type_basic _detect_device_type_ai _set_device_type_manual
export -f _show_common_device_types