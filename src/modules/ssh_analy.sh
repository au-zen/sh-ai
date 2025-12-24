#!/usr/bin/env bash

# ============================================================
# SH-AI AI 智能结果分析业务模块
# ============================================================
# 职责: AI 智能结果分析与建议
# 架构: 
#   - SSH 分析: 调用 ssh_exec 获取数据 → 直接在 output 中展示 → LLM 分析
#   - 文件分析: 直接分析文件内容 → 直接在 output 中展示 → LLM 分析
# 需求: 9.1, 9.2, 9.3, 9.4, 9.5

# 加载 AI 请求接口
# source "$(dirname "${BASH_SOURCE[0]}")/../core/ai_request.sh"

# @cmd 智能结果分析业务模块
# @alias ssh.analy
# @alias analyze
# @option --intent! <string> Analysis intent or problem description. Examples: analyze firewall config, analyze network interface, analyze system performance
# @option --target <user@host[:port]>  SSH 目标(可选)。如不提供,自动使用最后连接的目标。
# @flag --verbose Show detailed debug output
ssh_analy() {
    local intent=""
    local target=""
    
    # 优先使用 argc 变量
    if [[ -n "${argc_intent:-}" ]]; then
        intent="${argc_intent}"
        target="${argc_target:-}"
    else
        # 回退到自定义解析（兼容 JSON 输入和旧版调用）
        local input="${1:-}"
        
        if [[ "$input" == \{* ]]; then
            # JSON 输入模式
            if command -v jq &>/dev/null; then
                intent=$(echo "$input" | jq -r '.intent // empty' 2>/dev/null)
                target=$(echo "$input" | jq -r '.target // empty' 2>/dev/null)
            else
                _error "需要 jq 来解析 JSON 输入"
                return 1
            fi
        else
            # 普通参数模式
            intent="$input"
            target="${2:-}"
        fi
    fi
    
    # Trim whitespace from arguments
    intent=$(echo "$intent" | xargs)
    target=$(echo "$target" | xargs)
    
    # 处理 AI 模型可能传递的 "null" 字符串或空字符串
    if [[ "$target" == "null" || -z "$target" ]]; then
        target=""
    fi
    
    if [[ -z "$intent" ]]; then
        _error "请提供分析意图"
        _info "用法: ssh_analy '<分析意图>' [目标主机|文件路径]"
        _output_separator
        _output_header 3 "使用示例"        _output_code "bash" "ssh_analy '分析防火墙配置' root@192.168.1.1"
        _output_code "bash" "ssh_analy '分析配置文件' /etc/firewall.conf"
        _output_code "bash" "ssh_analy '分析系统性能'"
        return 1
    fi
    
    _output_header 2 "AI 智能结果分析"    
    # 添加元数据
    _add_metadata "operation" "ssh_analy"
    _add_metadata "intent" "$intent"
    
    # 显示分析信息
    _info "分析意图: $intent"
    
    # 判断分析类型：SSH 分析 vs 文件分析
    if [[ -n "$target" ]]; then
        if [[ -f "$target" ]]; then
            # 文件分析模式
            _info "分析类型: 文件分析"
            _info "目标文件: $target"
            _add_metadata "analysis_type" "file_analysis"
            _add_metadata "target_file" "$target"
            
            _analyze_file_with_ai "$intent" "$target"
        elif [[ "$target" =~ ^[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+(:([0-9]+))?$ ]]; then
            # SSH 分析模式
            _info "分析类型: SSH 分析"
            _info "目标主机: $target"
            _add_metadata "analysis_type" "ssh_analysis"
            _add_metadata "target" "$target"
            
            _analyze_ssh_with_ai "$intent" "$target"
        else
            _error "无效的目标: $target"
            _info "目标应该是 SSH 主机 (user@host[:port]) 或文件路径"
            return 1
        fi
    else
        # 如果没有指定目标，尝试获取最后连接的目标进行 SSH 分析
        # 注意：这是 SH-AI 本地状态，与 LLM session 无关
        if target=$(_get_last_connected_target); then
            _info "分析类型: SSH 分析"
            _info "目标主机: $target (使用最后连接的目标)"
            _add_metadata "analysis_type" "ssh_analysis"
            _add_metadata "target" "$target"
            
            _analyze_ssh_with_ai "$intent" "$target"
        else
            _error "未指定分析目标，且无可用连接"
            _info "请指定 SSH 目标或文件路径"
            return 1
        fi
    fi

}





# SSH 分析：生成命令并执行，直接展示结果供 LLM 分析
_analyze_ssh_with_ai() {
    local intent="$1"
    local target="$2"
    
    _output_separator
    _output_header 3 "生成分析命令"
    _info "正在生成分析命令..."
    
    # 获取设备类型（仅用于规则回退，不传递给 LLM）
    local device_type="unknown"
    if device_type=$(_get_cached_device_type "$target" 2>/dev/null); then
        [[ -z "$device_type" ]] && device_type="unknown"
    fi
    
    # 使用规则生成分析命令
    local analyze_cmd=""
    analyze_cmd=$(_generate_command_by_rules "$intent" "$device_type")
    
    if [[ -z "$analyze_cmd" ]]; then
        _error "无法生成分析命令（无匹配规则）"
        return 1
    fi
    
    _success "分析命令: $analyze_cmd"
    _add_metadata "analyze_command" "$analyze_cmd"
    
    # 调用 ssh_exec 获取数据（使用 output 系统）
    _output_separator
    _output_header 3 "执行命令并获取数据"
    
    local ssh_result=""
    local ssh_exit_code=0
    local temp_output=$(mktemp)
    
    # 设置临时的 LLM_OUTPUT 来捕获 ssh_exec 的结构化输出
    local original_llm_output="${LLM_OUTPUT:-}"
    local original_output_mode="${_OUTPUT_MODE:-}"
    export LLM_OUTPUT="$temp_output"
    
    # 重新检测输出模式，让 ssh_exec 使用新的 LLM_OUTPUT
    _detect_output_mode
    _register_exit_trap
    
    # 调用 ssh_exec（使用 JSON 格式传递参数）
    local exec_stderr=$(mktemp)
    local exec_json="{\"target\":\"$target\",\"command\":\"$analyze_cmd\"}"
    if ssh_exec "$exec_json" 2>"$exec_stderr"; then
        ssh_exit_code=0
    else
        ssh_exit_code=$?
        # 如果失败，显示错误信息
        if [[ -s "$exec_stderr" ]]; then
            _error "ssh_exec 执行失败："
            cat "$exec_stderr" >&2
        fi
    fi
    rm -f "$exec_stderr"
    
    # 手动触发 finalize 以确保数据被写入
    _finalize_output
    
    # 从 JSON 输出中提取数据
    if [[ -f "$temp_output" ]]; then
        if command -v jq >/dev/null 2>&1; then
            # 尝试解析 JSON
            local jq_error=$(mktemp)
            ssh_result=$(jq -r '.data.output // ""' "$temp_output" 2>"$jq_error")
            local jq_exit=$?
            
            if [[ $jq_exit -ne 0 || -z "$ssh_result" ]]; then
                # JSON 解析失败，显示错误并读取原始文件
                _info "JSON 解析失败 (退出码: $jq_exit)"
                if [[ -s "$jq_error" ]]; then
                    _info "jq 错误: $(cat "$jq_error")"
                fi
                _info "临时文件前100字符: $(head -c 100 "$temp_output")"
                ssh_result=$(cat "$temp_output")
            fi
            rm -f "$jq_error"
        else
            # 没有 jq，读取整个文件
            _info "jq 不可用，读取整个文件"
            ssh_result=$(cat "$temp_output")
        fi
    else
        _error "临时输出文件不存在: $temp_output"
    fi
    
    # 恢复原来的 LLM_OUTPUT 和输出模式
    if [[ -n "$original_llm_output" ]]; then
        export LLM_OUTPUT="$original_llm_output"
    else
        unset LLM_OUTPUT
    fi
    _OUTPUT_MODE="$original_output_mode"
    
    # 不要删除 temp_output，先提取数据
    
    if [[ $ssh_exit_code -eq 0 && -n "$ssh_result" ]]; then
        # 保存数据到文件（用于后续查看）
        local saved_file
        saved_file=$(_save_ssh_analysis_data "$intent" "$target" "$ssh_result")
        
        # 直接展示数据供 LLM 分析
        _output_separator
        _output_header 3 "分析数据"
        _output_code "text" "$ssh_result"
        
        # 设置结构化数据
        _set_data "command" "$analyze_cmd"
        _set_data "target" "$target"
        _set_data "output" "$ssh_result"
        _set_data "data_lines" "$(echo "$ssh_result" | wc -l)"
        _set_data "saved_file" "$saved_file"
        
        _output_separator
        _success "数据获取成功，请 LLM 直接分析以上输出"
        _info "数据行数: $(echo "$ssh_result" | wc -l)"
        if [[ -n "$saved_file" ]]; then
            _info "数据已保存: $saved_file"
        fi
        
        # 清理临时文件
        rm -f "$temp_output"
        return 0
    else
        _error "SSH 数据获取失败"
        if [[ -n "$ssh_result" ]]; then
            _info "错误信息："
            _output "$ssh_result"
        fi
        # 清理临时文件
        rm -f "$temp_output"
        return 1
    fi
}

# 文件分析：直接展示文件内容供 LLM 分析
_analyze_file_with_ai() {
    local intent="$1"
    local file_path="$2"
    
    _output_separator
    _output_header 3 "读取文件"
    _info "正在读取文件: $file_path"
    
    # 检查文件是否存在
    if [[ ! -f "$file_path" ]]; then
        _error "文件不存在: $file_path"
        return 1
    fi
    
    # 检查文件是否可读
    if [[ ! -r "$file_path" ]]; then
        _error "文件不可读: $file_path"
        return 1
    fi
    
    # 读取文件内容
    local file_content
    if file_content=$(cat "$file_path" 2>/dev/null); then
        _success "文件读取成功"
        _info "文件大小: $(du -h "$file_path" | cut -f1)"
        _info "文件行数: $(wc -l < "$file_path")"
        
        # 保存数据到文件（用于后续查看）
        local saved_file
        saved_file=$(_save_file_analysis_data "$intent" "$file_path" "$file_content")
        
        # 直接展示文件内容供 LLM 分析
        _output_separator
        _output_header 3 "文件内容"
        _output_code "text" "$file_content"
        
        # 设置结构化数据
        _set_data "source_file" "$file_path"
        _set_data "content" "$file_content"
        _set_data "data_lines" "$(echo "$file_content" | wc -l)"
        _set_data "saved_file" "$saved_file"
        
        _output_separator
        _success "文件读取成功，请 LLM 直接分析以上内容"
        _info "数据行数: $(echo "$file_content" | wc -l)"
        if [[ -n "$saved_file" ]]; then
            _info "数据已保存: $saved_file"
        fi
        
        return 0
    else
        _error "文件读取失败: $file_path"
        return 1
    fi
}







# 保存 SSH 分析数据
_save_ssh_analysis_data() {
    local intent="$1"
    local target="$2"
    local data="$3"
    
    # 创建 tmp 目录（使用绝对路径或基于 HOME 的路径）
    local tmp_dir="${SH_AI_TMP_DIR:-$HOME/.config/aichat/functions/agents/sh-ai/tmp}"
    if [[ ! -d "$tmp_dir" ]]; then
        mkdir -p "$tmp_dir" 2>/dev/null || {
            # 如果创建失败，使用系统临时目录
            tmp_dir="/tmp/sh-ai-analysis"
            mkdir -p "$tmp_dir"
        }
    fi
    
    # 生成文件名
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local safe_intent=$(echo "$intent" | tr -c '[:alnum:]' '_' | tr -s '_')
    local filename="ssh_${safe_intent}_${timestamp}.txt"
    local filepath="$tmp_dir/$filename"
    
    # 保存数据
    cat > "$filepath" << EOF
# SH-AI SSH 分析数据
生成时间: $(date)
分析意图: $intent
目标主机: $target
数据来源: SSH 远程执行

原始数据
$data

数据统计
数据行数: $(echo "$data" | wc -l)
数据大小: $(echo "$data" | wc -c) 字节
获取方式: 通过 ssh_exec 远程执行

EOF
    
    if [[ -f "$filepath" ]]; then
        # 返回文件路径（供调用者使用）
        echo "$filepath"
    else
        echo ""
    fi
}

# 保存文件分析数据
_save_file_analysis_data() {
    local intent="$1"
    local file_path="$2"
    local data="$3"
    
    # 创建 tmp 目录（使用绝对路径或基于 HOME 的路径）
    local tmp_dir="${SH_AI_TMP_DIR:-$HOME/.config/aichat/functions/agents/sh-ai/tmp}"
    if [[ ! -d "$tmp_dir" ]]; then
        mkdir -p "$tmp_dir" 2>/dev/null || {
            # 如果创建失败，使用系统临时目录
            tmp_dir="/tmp/sh-ai-analysis"
            mkdir -p "$tmp_dir"
        }
    fi
    
    # 生成文件名
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local safe_intent=$(echo "$intent" | tr -c '[:alnum:]' '_' | tr -s '_')
    local filename="file_${safe_intent}_${timestamp}.txt"
    local filepath="$tmp_dir/$filename"
    
    # 保存数据
    cat > "$filepath" << EOF
# SH-AI 文件分析数据
生成时间: $(date)
分析意图: $intent
目标文件: $file_path
数据来源: 本地文件读取

原始数据
$data

数据统计
数据行数: $(echo "$data" | wc -l)
数据大小: $(echo "$data" | wc -c) 字节
文件路径: $file_path

EOF
    
    if [[ -f "$filepath" ]]; then
        # 返回文件路径（供调用者使用）
        echo "$filepath"
    else
        echo ""
    fi
}

# 批量分析功能
ssh_analy_batch() {
    local intent="${1:-}"
    shift
    local targets=("$@")
    
    if [[ -z "$intent" || ${#targets[@]} -eq 0 ]]; then
        _error "请提供分析意图和目标主机列表"
        _info "用法: ssh_analy_batch '<分析意图>' <目标1> <目标2> ..."
        return 1
    fi
    
    _output_header 2 "批量 AI 分析"    _info "分析意图: $intent"
    _info "目标数量: ${#targets[@]}"
    
    local success_count=0
    local failed_count=0
    
    for target in "${targets[@]}"; do
        _output_separator
        _output_header 3 "分析目标: $target"        
        if ssh_analy "$intent" "$target"; then
            ((success_count++))
            _success "目标 $target 分析成功"
        else
            ((failed_count++))
            _error "目标 $target 分析失败"
        fi
    done
    
    # 显示批量分析结果
    _output_separator
    _output_header 3 "批量分析结果"    
    declare -A batch_result
    batch_result["总目标数"]="${#targets[@]}"
    batch_result["成功数量"]="$success_count"
    batch_result["失败数量"]="$failed_count"
    batch_result["成功率"]="$((success_count * 100 / ${#targets[@]}))%"
    
    _output_table batch_result
    
    if [[ $failed_count -eq 0 ]]; then
        _success "所有目标分析成功"
        return 0
    else
        _warning "部分目标分析失败"
        return 1
    fi
}

# 分析历史记录功能
ssh_analy_history() {
    local target="${1:-}"
    local limit="${2:-10}"
    
    _output_header 2 "分析历史记录"    
    if [[ -n "$target" ]]; then
        _info "查询目标: $target"
    else
        _info "显示所有目标的分析历史"
    fi
    
    _info "显示最近 $limit 条记录"
    
    # 这里可以集成历史记录功能
    # 当前为基础实现
    _info "历史记录功能将在后续版本中实现"
    _info "当前可以查看 tmp/ 目录中的分析记录"
    
    return 0
}

# 导出函数
export -f ssh_analy ssh_analy_batch ssh_analy_history _analyze_ssh_with_ai _analyze_file_with_ai _save_ssh_analysis_data _save_file_analysis_data
