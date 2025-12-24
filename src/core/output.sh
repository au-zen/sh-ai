#!/usr/bin/env bash

# ============================================================
# SH-AI 输出格式化核心模块
# ============================================================
# 职责: 统一的纯文本格式输出
# 需求: 10.1, 10.2, 10.3, 10.4, 10.5

# ============================================================
# 模式检测系统 - Global State Variables
# ============================================================
# 需求: 1.1, 1.4

# 输出模式: "aichat" 或 "cli"
_OUTPUT_MODE=""

# 原始输出模式: true 表示绕过 JSON 包装
_RAW_OUTPUT_MODE=false

# ============================================================
# 输出缓冲系统 - Buffer Data Structures
# ============================================================
# 需求: 7.1, 7.4

# 消息缓冲区数组 - 存储所有输出消息（格式化显示内容）
declare -a _OUTPUT_BUFFER=()

# 状态级别数组 - 跟踪每条消息的状态级别
declare -a _OUTPUT_STATUS_LEVELS=()

# 元数据关联数组 - 存储结构化元数据（纯数据，供模型使用）
declare -A _OUTPUT_METADATA=()

# 纯数据缓冲区 - 存储不包含格式化的纯数据（供模型读取）
declare -A _OUTPUT_DATA=()

# 缓冲区大小限制 - 防止缓冲区溢出
# 需求: 5.5
readonly MAX_BUFFER_SIZE=1000

# ============================================================
# 模式检测函数
# ============================================================
# 需求: 1.1, 1.2, 1.3, 1.4, 1.5, 10.1, 10.4

# 验证 $LLM_OUTPUT 是否可写
# 返回: 0 表示有效, 1 表示无效
_validate_llm_output() {
    # 检查 $LLM_OUTPUT 是否设置且非空
    if [[ -z "${LLM_OUTPUT:-}" ]]; then
        return 1
    fi
    
    # 获取目录路径
    local dir
    dir=$(dirname "$LLM_OUTPUT")
    
    # 检查目录是否存在且可写
    if [[ -d "$dir" ]] && [[ -w "$dir" ]]; then
        return 0
    fi
    
    return 1
}

# 检测并设置输出模式
# 返回: 0 表示 AIChat 模式, 1 表示 CLI 模式
_detect_output_mode() {
    # 检查 $LLM_OUTPUT 是否设置且可写
    if [[ -n "${LLM_OUTPUT:-}" ]]; then
        # 验证可写性
        if _validate_llm_output; then
            _OUTPUT_MODE="aichat"
            return 0
        else
            # 验证失败，记录警告并回退到 CLI 模式
            echo "Warning: \$LLM_OUTPUT is set but not writable, falling back to CLI mode" >&2
        fi
    fi
    
    # 默认为 CLI 模式
    _OUTPUT_MODE="cli"
    return 0
}

# 检查是否为 AIChat 模式 (且非原始输出模式)
# 返回: 0 表示是, 1 表示否
_is_aichat_mode() {
    [[ "$_OUTPUT_MODE" == "aichat" ]] && [[ "$_RAW_OUTPUT_MODE" != true ]]
}

# 检查是否为原始输出模式
# 返回: 0 表示是, 1 表示否
_is_raw_output_mode() {
    [[ "$_RAW_OUTPUT_MODE" == true ]]
}

# ============================================================
# 原始输出控制函数
# ============================================================
# 需求: 10.1, 10.2, 10.3, 10.4

# 启用原始输出模式 (绕过 JSON 包装)
_set_raw_output_mode() {
    _RAW_OUTPUT_MODE=true
    # 禁用 EXIT trap 以防止 JSON 输出
    trap - EXIT
}

# 禁用原始输出模式 (恢复正常行为)
_unset_raw_output_mode() {
    _RAW_OUTPUT_MODE=false
    # 重新启用 EXIT trap (如果需要)
    # 注意: 实际的 trap 设置将在输出缓冲系统实现时添加
}

# 检查原始模式状态 (辅助函数)
# 返回: 0 表示启用, 1 表示禁用
_check_raw_mode() {
    [[ "$_RAW_OUTPUT_MODE" == true ]]
}

# ============================================================
# 缓冲区管理函数
# ============================================================
# 需求: 7.1, 7.2, 7.5, 8.5

# 初始化/重置输出缓冲区
# 用途: 清空所有缓冲区和元数据，准备新的输出
_init_output_buffer() {
    _OUTPUT_BUFFER=()
    _OUTPUT_STATUS_LEVELS=()
    _OUTPUT_METADATA=()
    _OUTPUT_DATA=()
}

# 向缓冲区追加消息
# 参数:
#   $1 - 消息内容
#   $2 - 状态级别 (可选: "info", "success", "warning", "error")
# 用途: 在 AIChat 模式下累积输出消息
# 需求: 5.5 - 包含缓冲区溢出保护
_append_to_buffer() {
    local message="$1"
    local status_level="${2:-info}"
    
    # 验证状态级别
    case "$status_level" in
        info|success|warning|error)
            # 有效的状态级别
            ;;
        *)
            # 无效状态级别，默认为 info
            status_level="info"
            ;;
    esac
    
    # 检查缓冲区大小，防止溢出
    # 需求: 5.5
    if [[ ${#_OUTPUT_BUFFER[@]} -ge $MAX_BUFFER_SIZE ]]; then
        # 缓冲区已满，强制终结并重置
        echo "Warning: Output buffer size limit ($MAX_BUFFER_SIZE) reached, forcing finalization" >&2
        
        # 添加警告消息到当前缓冲区
        _OUTPUT_BUFFER+=("警告: 输出缓冲区已达到大小限制，已自动终结")
        _OUTPUT_STATUS_LEVELS+=("warning")
        
        # 写入当前缓冲区内容
        if _is_aichat_mode; then
            _write_json_output
        fi
        
        # 重置缓冲区
        _init_output_buffer
        
        # 添加新消息到重置后的缓冲区
        _OUTPUT_BUFFER+=("$message")
        _OUTPUT_STATUS_LEVELS+=("$status_level")
        
        return 0
    fi
    
    # 追加消息和状态级别
    _OUTPUT_BUFFER+=("$message")
    _OUTPUT_STATUS_LEVELS+=("$status_level")
}

# 获取缓冲区的整体状态
# 返回: 最高优先级的状态 (error > warning > success > info)
# 用途: 确定最终 JSON 响应的状态字段
_get_buffer_status() {
    local has_error=false
    local has_warning=false
    local has_success=false
    
    # 遍历所有状态级别
    for status in "${_OUTPUT_STATUS_LEVELS[@]}"; do
        case "$status" in
            error)
                has_error=true
                ;;
            warning)
                has_warning=true
                ;;
            success)
                has_success=true
                ;;
        esac
    done
    
    # 按优先级返回状态
    if [[ "$has_error" == true ]]; then
        echo "error"
    elif [[ "$has_warning" == true ]]; then
        echo "warning"
    elif [[ "$has_success" == true ]]; then
        echo "success"
    else
        echo "info"
    fi
}

# 清除输出缓冲区
# 用途: 测试和重置场景
_clear_buffer() {
    _init_output_buffer
}

# ============================================================
# JSON 生成系统
# ============================================================
# 需求: 2.5, 3.2, 3.3

# JSON 字符串转义函数
# 参数:
#   $1 - 需要转义的字符串
# 返回: 转义后的字符串 (适合放入 JSON 字符串值中)
# 用途: 确保字符串可以安全地嵌入 JSON 中
_escape_json_string() {
    local input="$1"
    local output=""
    
    # 使用 sed 进行多次替换以转义特殊字符
    # 注意: 必须先转义反斜杠，然后再转义其他字符
    output=$(echo -n "$input" | \
        sed 's/\\/\\\\/g' | \
        sed 's/"/\\"/g' | \
        sed ':a;N;$!ba;s/\n/\\n/g' | \
        sed 's/\t/\\t/g' | \
        sed 's/\r/\\r/g')
    
    echo -n "$output"
}

# JSON 响应构建函数
# 返回: 完整的 JSON 响应对象
# 用途: 将缓冲区内容组合成结构化的 JSON 响应
# 需求: 2.2, 2.3, 2.4, 8.1, 8.2, 8.3, 8.4, 5.9
# 重要: data 字段包含纯数据（供模型读取），display 字段包含格式化消息（仅用于显示）
_build_json_response() {
    local status
    local display_message=""
    local json_output=""
    
    # 获取整体状态
    status=$(_get_buffer_status)
    
    # 组合所有缓冲的格式化消息（用于 display 字段）
    if [[ ${#_OUTPUT_BUFFER[@]} -gt 0 ]]; then
        # 使用换行符连接所有消息
        local first=true
        for msg in "${_OUTPUT_BUFFER[@]}"; do
            if [[ "$first" == true ]]; then
                display_message="$msg"
                first=false
            else
                display_message="${display_message}\n${msg}"
            fi
        done
    fi
    
    # 转义显示消息内容
    local escaped_display
    escaped_display=$(_escape_json_string "$display_message")
    
    # 构建基础 JSON 对象（保留 message 字段用于向后兼容，指向 display）
    json_output="{\"status\":\"${status}\",\"message\":\"${escaped_display}\""
    
    # 添加 display 字段（格式化消息，仅用于终端显示）
    if [[ -n "$display_message" ]]; then
        json_output="${json_output},\"display\":\"${escaped_display}\""
    fi
    
    # 构建 data 字段（纯数据，供模型读取，不包含格式化）
    local has_data=false
    json_output="${json_output},\"data\":{"
    
    # 首先添加纯数据（_OUTPUT_DATA）
    local first=true
    for key in "${!_OUTPUT_DATA[@]}"; do
        local escaped_key
        local escaped_value
        escaped_key=$(_escape_json_string "$key")
        escaped_value=$(_escape_json_string "${_OUTPUT_DATA[$key]}")
        
        if [[ "$first" == true ]]; then
            json_output="${json_output}\"${escaped_key}\":\"${escaped_value}\""
            first=false
            has_data=true
        else
            json_output="${json_output},\"${escaped_key}\":\"${escaped_value}\""
        fi
    done
    
    # 然后添加元数据（也作为纯数据的一部分）
    for key in "${!_OUTPUT_METADATA[@]}"; do
        # 如果键已存在于 _OUTPUT_DATA 中，跳过（避免重复）
        if [[ -z "${_OUTPUT_DATA[$key]:-}" ]]; then
            local escaped_key
            local escaped_value
            escaped_key=$(_escape_json_string "$key")
            # 清理元数据值中的格式化标记
            local clean_value="${_OUTPUT_METADATA[$key]}"
            clean_value=$(echo "$clean_value" | sed 's/✅//g' | sed 's/❌//g' | sed 's/⚠️//g' | sed 's/💡//g' | sed 's/🔍//g')
            clean_value=$(echo "$clean_value" | sed 's/^成功:[[:space:]]*//' | sed 's/^信息:[[:space:]]*//' | sed 's/^错误:[[:space:]]*//' | sed 's/^警告:[[:space:]]*//')
            escaped_value=$(_escape_json_string "$clean_value")
            
            if [[ "$first" == true ]]; then
                json_output="${json_output}\"${escaped_key}\":\"${escaped_value}\""
                first=false
                has_data=true
            else
                json_output="${json_output},\"${escaped_key}\":\"${escaped_value}\""
            fi
        fi
    done
    
    # 关闭 data 字段
    json_output="${json_output}}"
    
    # 关闭 JSON 对象
    json_output="${json_output}}"
    
    echo -n "$json_output"
}

# JSON 验证函数
# 参数:
#   $1 - 需要验证的 JSON 字符串
# 返回: 0 表示有效, 1 表示无效
# 用途: 在写入前验证 JSON 结构的有效性
# 需求: 5.3
_validate_json() {
    local json="$1"
    
    # 检查 JSON 是否为空
    if [[ -z "$json" ]]; then
        return 1
    fi
    
    # 检查是否以 { 开头并以 } 结尾
    if [[ ! "$json" =~ ^\{.*\}$ ]]; then
        return 1
    fi
    
    # 计数大括号和方括号的平衡性
    local open_braces=0
    local open_brackets=0
    local in_string=false
    local escaped=false
    local i
    
    for ((i=0; i<${#json}; i++)); do
        local char="${json:$i:1}"
        
        # 处理转义字符
        if [[ "$escaped" == true ]]; then
            escaped=false
            continue
        fi
        
        if [[ "$char" == "\\" ]]; then
            escaped=true
            continue
        fi
        
        # 处理字符串状态
        if [[ "$char" == "\"" ]]; then
            if [[ "$in_string" == true ]]; then
                in_string=false
            else
                in_string=true
            fi
            continue
        fi
        
        # 只在字符串外部计数括号
        if [[ "$in_string" == false ]]; then
            case "$char" in
                "{")
                    ((open_braces++))
                    ;;
                "}")
                    ((open_braces--))
                    ;;
                "[")
                    ((open_brackets++))
                    ;;
                "]")
                    ((open_brackets--))
                    ;;
            esac
            
            # 如果括号数量变为负数，说明不平衡
            if [[ $open_braces -lt 0 ]] || [[ $open_brackets -lt 0 ]]; then
                return 1
            fi
        fi
    done
    
    # 检查最终括号是否平衡
    if [[ $open_braces -ne 0 ]] || [[ $open_brackets -ne 0 ]]; then
        return 1
    fi
    
    # 检查是否有未闭合的字符串
    if [[ "$in_string" == true ]]; then
        return 1
    fi
    
    return 0
}

# ============================================================
# 元数据管理函数
# ============================================================
# 需求: 6.1, 6.2, 6.3, 6.4, 6.5

# 添加元数据到响应
# 参数:
#   $1 - 元数据键
#   $2 - 元数据值
# 用途: 向 JSON 响应的 data 字段添加结构化元数据
_add_metadata() {
    local key="$1"
    local value="$2"
    
    # 验证参数
    if [[ -z "$key" ]]; then
        echo "Warning: _add_metadata called with empty key" >&2
        return 1
    fi
    
    # 添加到元数据关联数组
    _OUTPUT_METADATA["$key"]="$value"
    
    return 0
}

# 设置纯数据（供模型读取，不包含格式化）
# 参数:
#   $1 - 数据键
#   $2 - 数据值（纯文本，无 Markdown/图标）
# 用途: 向 JSON 响应的 data 字段添加纯数据，模型只读取此字段
# 需求: 5.9 - 确保 Markdown 格式不影响模型
_set_data() {
    local key="$1"
    local value="$2"
    
    # 验证参数
    if [[ -z "$key" ]]; then
        echo "Warning: _set_data called with empty key" >&2
        return 1
    fi
    
    # 清理值中的格式化标记（移除状态图标、Markdown 标记等）
    local clean_value="$value"
    # 移除状态图标
    clean_value=$(echo "$clean_value" | sed 's/✅//g' | sed 's/❌//g' | sed 's/⚠️//g' | sed 's/💡//g' | sed 's/🔍//g')
    # 移除状态前缀（成功:、信息:、错误:等）
    clean_value=$(echo "$clean_value" | sed 's/^成功:[[:space:]]*//' | sed 's/^信息:[[:space:]]*//' | sed 's/^错误:[[:space:]]*//' | sed 's/^警告:[[:space:]]*//')
    # 移除 Markdown 代码块标记
    clean_value=$(echo "$clean_value" | sed '/^```/d' | sed 's/```//g')
    # 移除多余空白
    clean_value=$(echo "$clean_value" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    # 添加到纯数据关联数组
    _OUTPUT_DATA["$key"]="$clean_value"
    
    return 0
}

# ============================================================
# 输出写入系统
# ============================================================
# 需求: 2.1, 5.1, 5.4, 4.1, 4.2, 4.3, 7.3

# JSON 输出写入函数
# 用途: 将缓冲区内容作为 JSON 写入 $LLM_OUTPUT
# 返回: 0 表示成功, 1 表示失败
# 需求: 2.1, 5.1, 5.4
_write_json_output() {
    # 验证 $LLM_OUTPUT 可写性
    if ! _validate_llm_output; then
        echo "Error: Cannot write to \$LLM_OUTPUT: ${LLM_OUTPUT:-not set}" >&2
        return 1
    fi
    
    # 生成 JSON 响应
    local json_response
    json_response=$(_build_json_response)
    
    # 验证 JSON 有效性
    if ! _validate_json "$json_response"; then
        echo "Error: Generated invalid JSON response" >&2
        echo "JSON content: $json_response" >&2
        
        # 如果 JSON 无效，生成一个最小的有效 JSON 错误响应
        local error_json='{"status":"error","message":"输出格式错误"}'
        if _validate_json "$error_json"; then
            echo "$error_json" > "$LLM_OUTPUT" 2>/dev/null || {
                echo "Error: Failed to write error JSON to \$LLM_OUTPUT" >&2
                return 1
            }
            return 0
        fi
        
        return 1
    fi
    
    # 写入 JSON 到 $LLM_OUTPUT (只输出 JSON，错误信息只到 stderr)
    if ! echo "$json_response" > "$LLM_OUTPUT" 2>/dev/null; then
        echo "Error: Failed to write JSON to \$LLM_OUTPUT" >&2
        return 1
    fi
    
    return 0
}

# 直接输出写入函数 (CLI 模式)
# 参数:
#   $1 - 消息内容
# 用途: 在 CLI 模式下直接写入 stdout，不使用缓冲
# 需求: 4.1, 4.2, 4.3
_write_direct_output() {
    local message="$1"
    
    # 直接写入 stdout，保持当前输出格式
    echo "$message"
}

# 输出终结函数
# 用途: 在脚本退出时处理输出终结
# 需求: 7.3
_finalize_output() {
    # 只在 AIChat 模式下执行终结
    if _is_aichat_mode; then
        # 写入 JSON 输出
        _write_json_output
    fi
    # CLI 模式下不需要终结 (已经直接写入)
}

# 注册 EXIT trap 以调用 _finalize_output
# 注意: 只在 AIChat 模式且非原始输出模式下注册
# 在模块初始化时，如果检测到 AIChat 模式，则注册 trap
_register_exit_trap() {
    if _is_aichat_mode && ! _is_raw_output_mode; then
        trap '_finalize_output' EXIT
    fi
}

# 输出路径管理
_get_output_path() {
    echo "${LLM_OUTPUT:-/dev/stdout}"
}

# 基础输出函数
# 需求: 1.5, 4.4, 7.1, 10.2, 10.4
_output() {
    local message="$1"
    
    # 检查原始输出模式 - 优先级最高
    if _is_raw_output_mode; then
        # 原始模式: 直接写入 stdout
        echo "$message"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        # AIChat 模式: 缓冲消息
        _append_to_buffer "$message" "info"
    else
        # CLI 模式: 直接写入 stdout
        _write_direct_output "$message"
    fi
}

# 标题输出
# 需求: 3.1, 3.4, 4.5
_output_header() {
    local level="$1"
    local title="$2"
    local icon="${3:-}"
    
    local formatted="$title"
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$formatted"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        _append_to_buffer "$formatted" "info"
    else
        _write_direct_output "$formatted"
    fi
}

# 分隔线输出
# 需求: 3.1, 3.4, 4.5
_output_separator() {
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo ""
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        _append_to_buffer "" "info"
    else
        _write_direct_output ""
    fi
}

# 代码块输出
# 需求: 3.1, 3.4, 4.5
_output_code() {
    local language="${1:-bash}"
    local code="$2"
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$code"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        _append_to_buffer "$code" "info"
    else
        _write_direct_output "$code"
    fi
}

# 成功信息
# 需求: 8.1
_success() {
    local message="$1"
    local formatted="成功: $message"
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$formatted"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        # AIChat 模式: 缓冲消息并标记为 success 状态
        _append_to_buffer "$formatted" "success"
    else
        # CLI 模式: 直接输出
        _write_direct_output "$formatted"
    fi
}

# 错误信息
# 需求: 8.2
_error() {
    local message="$1"
    local formatted="错误: $message"
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$formatted"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        # AIChat 模式: 缓冲消息并标记为 error 状态
        _append_to_buffer "$formatted" "error"
    else
        # CLI 模式: 直接输出
        _write_direct_output "$formatted"
    fi
}

# 警告信息
# 需求: 8.3
_warning() {
    local message="$1"
    local formatted="警告: $message"
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$formatted"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        # AIChat 模式: 缓冲消息并标记为 warning 状态
        _append_to_buffer "$formatted" "warning"
    else
        # CLI 模式: 直接输出
        _write_direct_output "$formatted"
    fi
}

# 信息输出
# 需求: 8.4
_info() {
    local message="$1"
    local formatted="信息: $message"
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$formatted"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        # AIChat 模式: 缓冲消息并标记为 info 状态
        _append_to_buffer "$formatted" "info"
    else
        # CLI 模式: 直接输出
        _write_direct_output "$formatted"
    fi
}

# 执行信息
# 需求: 3.1, 3.4, 4.5
_exec_info() {
    local message="$1"
    local formatted="执行: $message"
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$formatted"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        _append_to_buffer "$formatted" "info"
    else
        _write_direct_output "$formatted"
    fi
}

# 分析信息
# 需求: 3.1, 3.4, 4.5
_analyze_info() {
    local message="$1"
    local formatted="分析: $message"
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$formatted"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        _append_to_buffer "$formatted" "info"
    else
        _write_direct_output "$formatted"
    fi
}

# 连接信息
# 需求: 3.1, 3.4, 4.5
_connect_info() {
    local message="$1"
    local formatted="连接: $message"
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$formatted"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        _append_to_buffer "$formatted" "info"
    else
        _write_direct_output "$formatted"
    fi
}

# 断开连接信息
# 需求: 3.1, 3.4, 4.5
_disconnect_info() {
    local message="$1"
    local formatted="断开: $message"
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$formatted"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        _append_to_buffer "$formatted" "info"
    else
        _write_direct_output "$formatted"
    fi
}

# 文件信息
# 需求: 3.1, 3.4, 4.5
_file_info() {
    local message="$1"
    local formatted="文件: $message"
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$formatted"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        _append_to_buffer "$formatted" "info"
    else
        _write_direct_output "$formatted"
    fi
}

# 输入提示
# 需求: 3.1, 3.4, 4.5
_input_prompt() {
    local message="$1"
    local formatted="输入: $message"
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$formatted"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        _append_to_buffer "$formatted" "info"
    else
        _write_direct_output "$formatted"
    fi
}

# 列表输出
# 需求: 3.1, 3.4, 4.5
_output_list() {
    local items=("$@")
    for item in "${items[@]}"; do
        local formatted="$item"
        
        # 检查原始输出模式
        if _is_raw_output_mode; then
            echo "$formatted"
        elif _is_aichat_mode; then
            _append_to_buffer "$formatted" "info"
        else
            _write_direct_output "$formatted"
        fi
    done
}

# 表格输出 (简单的两列表格)
# 需求: 3.1, 3.4, 4.5
_output_table() {
    local -n table_data=$1
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        for key in "${!table_data[@]}"; do
            echo "$key: ${table_data[$key]}"
        done
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        for key in "${!table_data[@]}"; do
            _append_to_buffer "$key: ${table_data[$key]}" "info"
        done
    else
        for key in "${!table_data[@]}"; do
            _write_direct_output "$key: ${table_data[$key]}"
        done
    fi
}

# 状态输出 (带颜色的状态指示)
# 需求: 3.1, 3.4, 4.5
_output_status() {
    local status="$1"
    local message="$2"
    local formatted=""
    local status_level="info"
    
    case "$status" in
        "success"|"ok"|"connected")
            formatted="$message"
            status_level="success"
            ;;
        "error"|"failed"|"disconnected")
            formatted="$message"
            status_level="error"
            ;;
        "warning"|"pending")
            formatted="$message"
            status_level="warning"
            ;;
        "info"|"unknown")
            formatted="$message"
            status_level="info"
            ;;
        *)
            formatted="$message"
            status_level="info"
            ;;
    esac
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$formatted"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        _append_to_buffer "$formatted" "$status_level"
    else
        _write_direct_output "$formatted"
    fi
}

# 进度输出
# 需求: 3.1, 3.4, 4.5
_output_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-处理中}"
    
    local percentage=$((current * 100 / total))
    local formatted="$message: ${percentage}% (${current}/${total})"
    
    # 检查原始输出模式
    if _is_raw_output_mode; then
        echo "$formatted"
        return 0
    fi
    
    # 检查 AIChat 模式
    if _is_aichat_mode; then
        _append_to_buffer "$formatted" "info"
    else
        _write_direct_output "$formatted"
    fi
}

# 调试输出 (仅在调试模式下输出)
_debug() {
    local message="$1"
    if [[ "${SH_AI_DEBUG_ENABLED:-false}" == "true" ]]; then
        _output "调试: $message"
    fi
}

# 详细输出 (仅在详细模式下输出)
_verbose() {
    local message="$1"
    if [[ "${SH_AI_VERBOSE_ENABLED:-false}" == "true" ]]; then
        _output "详细: $message"
    fi
}

# 输出模块初始化检查
_output_module_check() {
    # 检查输出路径是否可写
    local output_path
    output_path=$(_get_output_path)
    
    if [[ "$output_path" != "/dev/stdout" ]] && [[ ! -w "$(dirname "$output_path")" ]]; then
        echo "警告: 输出路径不可写: $output_path" >&2
        return 1
    fi
    
    return 0
}

# ============================================================
# 模块初始化
# ============================================================
# 需求: 1.1, 1.5, 4.4

# 在模块加载时检测输出模式
_detect_output_mode

# 注册 EXIT trap (如果在 AIChat 模式)
_register_exit_trap

# 导出核心函数
export -f _output _output_header _output_separator _output_code
export -f _success _error _warning _info _exec_info _analyze_info
export -f _connect_info _disconnect_info _file_info _input_prompt
export -f _output_list _output_table _output_status _output_progress
export -f _debug _verbose _output_module_check

# 导出模式检测函数
export -f _detect_output_mode _is_aichat_mode _is_raw_output_mode _validate_llm_output

# 导出原始输出控制函数
export -f _set_raw_output_mode _unset_raw_output_mode _check_raw_mode

# 导出缓冲区管理函数
export -f _init_output_buffer _append_to_buffer _get_buffer_status _clear_buffer

# 导出 JSON 生成函数
export -f _escape_json_string _build_json_response _validate_json

# 导出元数据管理函数
export -f _add_metadata _set_data

# 导出输出写入函数
export -f _write_json_output _write_direct_output _finalize_output _register_exit_trap