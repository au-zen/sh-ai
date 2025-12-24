#!/usr/bin/env bash

# ============================================================
# SH-AI 离线文件分析模块
# ============================================================
# 职责: 分析已保存的 SSH/文件分析数据
# 用途: 当 ssh_analy 只是获取了数据但未分析时，用此工具进行后续分析
# 特别适合: Qwen 等小模型，避免在函数调用中直接分析大量数据

# 加载依赖
# source "$(dirname "${BASH_SOURCE[0]}")/../core/output.sh"

# @cmd Analyze saved data files. Specialized for analyzing SSH/file analysis data saved in tmp directory. This is Step 2 of two-step analysis: after ssh_analy retrieves data, use this tool to analyze the saved file.
# @alias analy.file
# @alias af
# @option --file <path> File path to analyze. If not provided lists available files for user selection.
# @option --intent <string> Analysis intent (optional). If not provided extracts from file.
# @flag --list List all analyzable files
# @flag --verbose Show detailed debug output
ssh_analy_file() {
    local file_path=""
    local intent=""
    local list_mode=false
    
    # 参数解析
    if [[ -n "${argc_file:-}" ]]; then
        file_path="${argc_file}"
    fi
    
    if [[ -n "${argc_intent:-}" ]]; then
        intent="${argc_intent}"
    fi
    
    if [[ "${argc_list:-}" == "true" ]]; then
        list_mode=true
    fi
    
    # 回退到位置参数
    if [[ -z "$file_path" && $# -gt 0 ]]; then
        file_path="$1"
        shift
    fi
    
    if [[ -z "$intent" && $# -gt 0 ]]; then
        intent="$1"
        shift
    fi
    
    # 默认 tmp 目录
    local tmp_dir="${SH_AI_TMP_DIR:-$HOME/.config/aichat/functions/agents/sh-ai/tmp}"
    
    # 列出可用文件模式
    if [[ "$list_mode" == true ]]; then
        _list_analysis_files "$tmp_dir"
        return 0
    fi
    
    # 如果没有提供文件路径，列出文件让用户选择
    if [[ -z "$file_path" ]]; then
        _output_header 2 "选择要分析的文件"
        _list_analysis_files "$tmp_dir"
        _output ""
        _info "用法: ssh_analy_file <文件路径> [分析意图]"
        _info "示例: ssh_analy_file ~/.config/aichat/functions/agents/sh-ai/tmp/ssh_xxx.txt"
        return 1
    fi
    
    # 如果提供的是文件名（不是完整路径），自动补全
    if [[ ! -f "$file_path" && ! "$file_path" =~ ^/ ]]; then
        # 尝试在 tmp 目录中查找
        local possible_file="$tmp_dir/$file_path"
        if [[ -f "$possible_file" ]]; then
            file_path="$possible_file"
        else
            # 尝试模糊匹配
            local matches=$(find "$tmp_dir" -name "*${file_path}*" -type f 2>/dev/null)
            local match_count=$(echo "$matches" | grep -c '^' 2>/dev/null || echo 0)
            
            if [[ $match_count -eq 1 ]]; then
                file_path="$matches"
                _info "自动匹配到文件: $file_path"
            elif [[ $match_count -gt 1 ]]; then
                _error "找到多个匹配的文件："
                echo "$matches"
                _info "请使用更具体的文件名"
                return 1
            else
                _error "文件不存在: $file_path"
                _info "使用 --list 查看所有可用文件"
                return 1
            fi
        fi
    fi
    
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
    
    _output_header 2 "离线数据分析"
    _info "文件路径: $file_path"
    
    # 从文件中提取元数据和数据
    local file_metadata
    local file_data
    local analysis_intent
    local data_source
    
    # 解析文件内容
    _parse_analysis_file "$file_path"
    
    # 如果用户提供了意图，使用用户的；否则使用文件中的
    if [[ -n "$intent" ]]; then
        analysis_intent="$intent"
    elif [[ -n "$PARSED_INTENT" ]]; then
        analysis_intent="$PARSED_INTENT"
    else
        analysis_intent="数据分析"
    fi
    
    data_source="${PARSED_SOURCE:-未知}"
    file_data="$PARSED_DATA"
    
    if [[ -z "$file_data" ]]; then
        _error "无法从文件中提取数据"
        return 1
    fi
    
    _info "分析意图: $analysis_intent"
    _info "数据来源: $data_source"
    _info "数据规模: $(echo "$file_data" | wc -l) 行"
    
    # 显示数据预览
    _output_separator
    _output_header 3 "数据预览（前20行）"
    _output_code "text" "$(echo "$file_data" | head -20)"
    local total_lines=$(echo "$file_data" | wc -l)
    if [[ $total_lines -gt 20 ]]; then
        _info "... (已截断，实际共 $total_lines 行)"
    fi
    
    # 启动分析流程
    _output_separator
    _output_header 3 "START ANALYSIS"
    
    _perform_analysis "$analysis_intent" "$data_source" "$file_data"
}

# 列出可分析的文件
_list_analysis_files() {
    local tmp_dir="$1"
    
    if [[ ! -d "$tmp_dir" ]]; then
        _warning "分析数据目录不存在: $tmp_dir"
        _info "还没有保存过任何分析数据"
        return 1
    fi
    
    local files=$(find "$tmp_dir" -type f \( -name "ssh_*.txt" -o -name "file_*.txt" \) 2>/dev/null | sort -r)
    
    if [[ -z "$files" ]]; then
        _warning "没有找到任何分析数据文件"
        _info "目录: $tmp_dir"
        return 1
    fi
    
    _output_header 3 "可分析的文件列表"
    _output ""
    
    local count=0
    while IFS= read -r file; do
        ((count++))
        local filename=$(basename "$file")
        local filesize=$(du -h "$file" | cut -f1)
        local filetime=$(stat -c %y "$file" 2>/dev/null || stat -f "%Sm" "$file" 2>/dev/null)
        
        # 尝试提取分析意图
        local file_intent=$(grep "^分析意图:" "$file" 2>/dev/null | cut -d: -f2- | xargs)
        local file_target=$(grep "^目标主机:\|^目标文件:" "$file" 2>/dev/null | cut -d: -f2- | xargs)
        
        _output "[$count] $filename"
        _output "    大小: $filesize | 时间: $filetime"
        if [[ -n "$file_intent" ]]; then
            _output "    意图: $file_intent"
        fi
        if [[ -n "$file_target" ]]; then
            _output "    目标: $file_target"
        fi
        _output ""
    done <<< "$files"
    
    _info "共找到 $count 个文件"
    _output ""
    _info "使用方法："
    _output "  1. 使用完整路径: ssh_analy_file /path/to/file.txt"
    _output "  2. 使用文件名: ssh_analy_file ssh_xxx.txt"
    _output "  3. 使用模糊匹配: ssh_analy_file 防火墙"
}

# 解析分析文件
_parse_analysis_file() {
    local file="$1"
    
    # 清空全局变量
    PARSED_INTENT=""
    PARSED_SOURCE=""
    PARSED_DATA=""
    
    # 读取文件内容
    local content=$(cat "$file")
    
    # 提取分析意图
    PARSED_INTENT=$(echo "$content" | grep "^分析意图:" | head -1 | cut -d: -f2- | xargs)
    
    # 提取数据来源
    local target_host=$(echo "$content" | grep "^目标主机:" | head -1 | cut -d: -f2- | xargs)
    local target_file=$(echo "$content" | grep "^目标文件:" | head -1 | cut -d: -f2- | xargs)
    
    if [[ -n "$target_host" ]]; then
        PARSED_SOURCE="$target_host"
    elif [[ -n "$target_file" ]]; then
        PARSED_SOURCE="$target_file"
    fi
    
    # 提取原始数据（在 "原始数据" 标记之后，"数据统计" 标记之前）
    PARSED_DATA=$(echo "$content" | awk '
        /^原始数据$/ { found=1; next }
        /^数据统计$/ { found=0 }
        found && NF { print }
    ')
}

# 执行分析（关键函数）
_perform_analysis() {
    local analysis_intent="$1"
    local data_source="$2"
    local data_content="$3"
    
    local data_lines=$(echo "$data_content" | wc -l)
    local data_chars=$(echo "$data_content" | wc -c)
    
    # 生成强制分析提示
    cat << 'EOF'

========================================================================
DATA ANALYSIS TASK (MUST COMPLETE)
========================================================================

You must now perform a complete professional analysis of the following data.
This is not optional, it is a mandatory task.

EOF

    echo "Task Information:"
    echo "  - Analysis Intent: $analysis_intent"
    echo "  - Data Source: $data_source"
    echo "  - Data Size: $data_lines lines / $data_chars characters"
    echo ""
    
    cat << 'EOF'
------------------------------------------------------------------------
COMPLETE DATA CONTENT
------------------------------------------------------------------------

EOF
    
    # 输出完整数据
    echo "$data_content"
    
    cat << 'EOF'

------------------------------------------------------------------------
ANALYSIS REPORT FORMAT REQUIREMENTS
------------------------------------------------------------------------

Please strictly follow the format below. All sections must be completed.

## 1. Key Information Analysis
Please identify and explain:
  - Current configuration status and parameters
  - Important metrics and values
  - System operation status
  [Write at least 3 specific points]

## 2. Problem Identification
List the problems found:
  - Security risks (mark level: HIGH/MEDIUM/LOW)
  - Configuration errors or unreasonable settings
  - Deviations from best practices
  [Explain the reason and impact for each problem]

## 3. Optimization Recommendations
Provide solutions for each problem:
  - Specific optimization steps
  - Commands to execute (if applicable)
  - Expected improvement effects
  [Recommendations should be executable and verifiable]

## 4. Follow-up Actions
Suggest what to do next:
  - Verification commands to execute
  - Metrics to monitor
  - Items to check regularly
  [Provide specific command examples]

------------------------------------------------------------------------
IMPORTANT REMINDERS
------------------------------------------------------------------------

1. DO NOT reply "data received" or "I see the data"
2. DO NOT just repeat the data content
3. MUST provide valuable technical analysis
4. MUST point out specific problems and solutions
5. USE Markdown format with clear structure

Now please start your professional analysis immediately and output a complete report in the format above.

EOF

    return 0
}

# @cmd Analyze latest saved data file. After ssh_analy retrieves data, this function MUST be called immediately for analysis. This is Step 2 of two-step analysis (MANDATORY). No parameters needed, automatically finds latest analysis file and presents data for LLM analysis.
# @alias analy.latest
# @alias al
# @flag --verbose Show detailed debug output
ssh_analy_file_latest() {
    local tmp_dir="${SH_AI_TMP_DIR:-$HOME/.config/aichat/functions/agents/sh-ai/tmp}"
    
    if [[ ! -d "$tmp_dir" ]]; then
        _error "分析数据目录不存在"
        return 1
    fi
    
    # 找到最新的文件
    local latest_file=$(find "$tmp_dir" -type f \( -name "ssh_*.txt" -o -name "file_*.txt" \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [[ -z "$latest_file" ]]; then
        _error "没有找到任何分析数据文件"
        return 1
    fi
    
    _info "分析最新文件: $(basename "$latest_file")"
    ssh_analy_file "$latest_file"
}

# 批量分析模式（分析最近N个文件）
ssh_analy_file_batch() {
    local count="${1:-5}"
    local tmp_dir="${SH_AI_TMP_DIR:-$HOME/.config/aichat/functions/agents/sh-ai/tmp}"
    
    _output_header 2 "批量文件分析"
    _info "分析最近 $count 个文件"
    
    if [[ ! -d "$tmp_dir" ]]; then
        _error "分析数据目录不存在"
        return 1
    fi
    
    # 找到最近的N个文件
    local files=$(find "$tmp_dir" -type f \( -name "ssh_*.txt" -o -name "file_*.txt" \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -"$count" | cut -d' ' -f2-)
    
    if [[ -z "$files" ]]; then
        _error "没有找到任何分析数据文件"
        return 1
    fi
    
    local total=0
    local success=0
    
    while IFS= read -r file; do
        ((total++))
        _output_separator
        _output_header 3 "分析文件 $total/$count: $(basename "$file")"
        
        if ssh_analy_file "$file"; then
            ((success++))
        fi
        
        # 添加分隔，避免混淆
        _output ""
        _output "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        _output ""
    done <<< "$files"
    
    _output_separator
    _output_header 3 "批量分析完成"
    _info "成功: $success / $total"
}

# 清理旧文件
ssh_analy_file_clean() {
    local days="${1:-7}"
    local tmp_dir="${SH_AI_TMP_DIR:-$HOME/.config/aichat/functions/agents/sh-ai/tmp}"
    
    _output_header 2 "清理旧分析文件"
    _info "删除 $days 天前的文件"
    
    if [[ ! -d "$tmp_dir" ]]; then
        _warning "分析数据目录不存在"
        return 0
    fi
    
    local old_files=$(find "$tmp_dir" -type f \( -name "ssh_*.txt" -o -name "file_*.txt" \) -mtime +"$days" 2>/dev/null)
    
    if [[ -z "$old_files" ]]; then
        _info "没有需要清理的文件"
        return 0
    fi
    
    local count=$(echo "$old_files" | wc -l)
    _info "找到 $count 个需要清理的文件"
    
    echo "$old_files" | while IFS= read -r file; do
        _info "删除: $(basename "$file")"
        rm -f "$file"
    done
    
    _success "清理完成"
}

# 导出函数（确保所有公开函数都被导出）
export -f ssh_analy_file ssh_analy_file_latest ssh_analy_file_batch ssh_analy_file_clean
export -f _list_analysis_files _parse_analysis_file _perform_analysis