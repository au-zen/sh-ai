#!/usr/bin/env bash

# ============================================================
# SH-AI 设备类型手动管理业务模块
# ============================================================
# 职责: 设备类型检测和手动管理功能
# 需求: 4.3, 4.4, 5.1, 5.2

# 为 LLM 导出可消费的设备上下文
_export_device_context() {
    local target="$1"
    local override_device_type="${2:-}"

    if [[ -z "$target" ]]; then
        _debug "跳过上下文导出：target 为空"
        return 1
    fi

    local ctx_dir="${SH_AI_DEVICE_CONTEXT_DIR:-$HOME/.config/aichat/hosts}"
    if ! mkdir -p "$ctx_dir" 2>/dev/null; then
        _warning "无法创建上下文目录: $ctx_dir"
        return 1
    fi

    local sanitized
    sanitized=$(echo "$target" | tr '[:upper:]' '[:lower:]')
    sanitized=$(echo "$sanitized" | sed 's/[^a-z0-9._-]/_/g')
    [[ -z "$sanitized" ]] && sanitized="unknown_target"

    local ctx_file="$ctx_dir/${sanitized}.ctx"

    local device_type="$override_device_type"
    local detection_method="unknown"
    local detection_epoch=""
    local detection_time="unknown"

    local cache_info
    if cache_info=$(_load_device_cache "$target" 2>/dev/null); then
        [[ -z "$device_type" ]] && device_type=$(echo "$cache_info" | grep '^device_type=' | cut -d'=' -f2)
        detection_method=$(echo "$cache_info" | grep '^method=' | cut -d'=' -f2)
        detection_epoch=$(echo "$cache_info" | grep '^timestamp=' | cut -d'=' -f2)
    fi

    [[ -z "$device_type" ]] && device_type="unknown"

    if [[ -n "$detection_epoch" ]]; then
        detection_time=$(date -d "@$detection_epoch" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "unknown")
    fi

    cat >"$ctx_file" <<EOF
### REMOTE_HOST_CONTEXT
target: $target
device_type: $device_type
detection_method: ${detection_method:-unknown}
detected_at: $detection_time

Rules:
- Treat this device_type as authoritative for $target.
- Do NOT猜测不同的设备类型。
- 若实际命令输出和该信息冲突，请报告不一致。
EOF

    echo "$ctx_file"
    return 0
}

# @cmd 自动检测设备类型。触发:用户说 'detect <target>'
# @alias ssh.detect
# @option --target <user@host[:port]> SSH 目标(可选)。如不提供,自动使用最后连接的目标。
# @option --device-type! <string> 设备类型 (linux/cisco/huawei/h3c/openwrt/freebsd/macos/windows/juniper/arista/mikrotik/fortinet/paloalto/unknown)
ssh_detect() {
    local target=""
    local force_detect="false"
    
    # 优先使用 argc 变量
    if [[ -n "${argc_target:-}" ]]; then
        target="${argc_target}"
        # 注意：argc 的 flag 变量可能是 "true" 字符串或空
        if [[ "${argc_force:-false}" == "true" ]]; then
            force_detect="true"
        fi
    else
        # 回退到自定义解析（兼容 JSON 输入和旧版调用）
        local input="${1:-}"
        
        if [[ "$input" == \{* ]]; then
            # JSON 输入模式
            if command -v jq &>/dev/null; then
                target=$(echo "$input" | jq -r '.target // empty' 2>/dev/null)
                local force_json=$(echo "$input" | jq -r '.force // false' 2>/dev/null)
                if [[ "$force_json" == "true" ]]; then
                    force_detect="true"
                fi
            else
                _error "需要 jq 来解析 JSON 输入"
                return 1
            fi
        else
            # 普通参数模式 - Parse arguments
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --force)
                        force_detect="true"
                        shift
                        ;;
                    *)
                        if [[ -z "$target" ]]; then
                            target="$1"
                        fi
                        shift
                        ;;
                esac
            done
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
            _error "请提供 SSH 目标"
            _info "用法: ssh_detect <目标主机> [--force]"
            return 1
        fi
    fi
    
    _output_header 2 "设备类型检测"    
    # 检查连接状态
    if ! _check_connection_health "$target"; then
        _error "连接不可用，请先建立连接: /connect $target"
        return 1
    fi
    
    # 显示检测信息
    if [[ "$force_detect" == "true" ]]; then
        _info "强制重新检测设备类型: $target"
    else
        _info "检测设备类型: $target"
    fi
    
    # 执行设备检测
    local device_type
    device_type=$(_detect_device_type_ai "$target" "$force_detect")
    local detect_result=$?
    
    case $detect_result in
        0)
            # 检测成功
            _success "设备类型检测完成: $target -> $device_type"
            
            # 显示设备类型信息
            _output_separator
            _output_header 3 "设备信息"            
            declare -A device_info
            device_info["目标主机"]="$target"
            device_info["设备类型"]="$device_type"
            device_info["检测方法"]="AI 自动检测"
            device_info["缓存状态"]="已保存"
            
            _output_table device_info
            
            # 显示支持的操作提示
            _info "现在可以使用 AI 智能命令: /ai '<意图>' $target"

            local ctx_file
            if ctx_file=$(_export_device_context "$target" "$device_type"); then
                _info "已生成 LLM 设备上下文: $ctx_file"
                export AI_SHELL_HOST_CONTEXT="$ctx_file"
                _set_data "host_context" "$ctx_file"
            else
                _warning "生成 LLM 设备上下文失败（不会影响 detect 结果）"
                unset AI_SHELL_HOST_CONTEXT
            fi
            return 0
            ;;
        1)
            # 检测失败
            _error "设备类型检测失败: $target"
            _warning "可能的原因："
            _output_list "网络连接问题" "设备不支持标准命令" "AI 服务不可用" "权限不足"
            _info "建议手动设置设备类型: /set_device_type $target <设备类型>"
            return 1
            ;;
        2)
            # 需要手动输入
            _warning "AI 自动检测失败，需要手动设置设备类型"
            _output_separator
            _output_header 3 "手动设置设备类型"            
            # 显示常见的设备类型
            _show_common_device_types
            
            _info "请使用以下命令手动设置："
            _output_code "bash" "/set_device_type $target <设备类型>"
            
            return 2
            ;;
        *)
            _error "未知的检测结果代码: $detect_result"
            return 1
            ;;
    esac
}


# @cmd 手动设置设备类型。触发:用户说 "set device type for <target> to <type>"
# @alias ssh.type
# @option --target <user@host[:port]> SSH 目标(可选)。如不提供,自动使用最后连接的目标。
# @option --device-type! <string> 设备类型 (linux/cisco/openwrt等)

ssh_set_device_type() {
    local target=""
    local device_type=""
    
    # 优先使用 argc 变量
    if [[ -n "${argc_target:-}" ]]; then
        target="${argc_target}"
        device_type="${argc_device_type:-}"
    else
        # 回退到自定义解析（兼容 JSON 输入和旧版调用）
        local input="${1:-}"
        
        if [[ "$input" == \{* ]]; then
            # JSON 输入模式
            if command -v jq &>/dev/null; then
                target=$(echo "$input" | jq -r '.target // empty' 2>/dev/null)
                device_type=$(echo "$input" | jq -r '.device_type // empty' 2>/dev/null)
            else
                _error "需要 jq 来解析 JSON 输入"
                return 1
            fi
        else
            # 普通参数模式
            target="$input"
            device_type="${2:-}"
        fi
    fi
    
    # Trim whitespace
    target=$(echo "$target" | xargs)
    device_type=$(echo "$device_type" | xargs)
    
    # 处理 AI 模型可能传递的 "null" 字符串或空字符串
    if [[ "$target" == "null" || -z "$target" ]]; then
        target=""
    fi
    if [[ "$device_type" == "null" || -z "$device_type" ]]; then
        device_type=""
    fi
    
    # 如果 target 为空，尝试获取最后连接的目标
    if [[ -z "$target" ]]; then
        if target=$(_get_last_connected_target); then
            _info "使用最后连接的目标: $target"
        else
            _error "请提供 SSH 目标和设备类型"
            _info "用法: ssh_set_device_type <目标主机> <设备类型>"
            _output_separator
            _show_common_device_types
            return 1
        fi
    fi
    
    if [[ -z "$device_type" ]]; then
        _error "请提供设备类型"
        _info "用法: ssh_set_device_type <目标主机> <设备类型>"
        _output_separator
        _show_common_device_types
        return 1
    fi
    
    _output_header 2 "手动设置设备类型"    
    # 显示设置信息
    _info "目标主机: $target"
    _info "设备类型: $device_type"
    
    # 执行手动设置
    local result_type
    if result_type=$(_set_device_type_manual "$target" "$device_type"); then
        _success "设备类型设置成功: $target -> $result_type"
        
        # 显示设置结果
        _output_separator
        _output_header 3 "设置结果"        
        declare -A setting_info
        setting_info["目标主机"]="$target"
        setting_info["设备类型"]="$result_type"
        setting_info["设置方法"]="手动设置"
        setting_info["缓存状态"]="已保存"
        setting_info["缓存有效期"]="24小时"
        
        _output_table setting_info
        
        # 验证设置是否生效
        local cached_type
        if cached_type=$(_get_cached_device_type "$target"); then
            if [[ "$cached_type" == "$result_type" ]]; then
                _success "缓存验证通过: $cached_type"
            else
                _warning "缓存验证失败: 期望 $result_type，实际 $cached_type"
            fi
        else
            _warning "无法验证缓存状态"
        fi
        
        # 显示后续操作建议
        _output_separator
        _output_header 3 "后续操作"
        _info "现在可以使用以下功能："
        _output_list "AI 智能命令: /ai '<意图>' $target" "直接执行命令: /exec $target '<命令>'" "结果分析: /analy '<分析意图>' $target"
        
        local ctx_file
        if ctx_file=$(_export_device_context "$target" "$result_type"); then
            _info "已更新 LLM 设备上下文: $ctx_file"
            _set_data "host_context" "$ctx_file"
        else
            _warning "LLM 设备上下文更新失败"
        fi

        return 0
    else
        _error "设备类型设置失败: $target"
        return 1
    fi
}

# 导出函数
export -f _export_device_context
