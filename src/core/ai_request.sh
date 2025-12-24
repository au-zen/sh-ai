#!/usr/bin/env bash

# ============================================================
# SH-AI AI Request Interface Module
# ============================================================
# 职责: 提供标准化的 AI 请求接口，与 agent framework 集成
# 用途: 替代直接的 aichat 调用，支持 RAG 知识库增强
# 框架依赖: sigoden/aichat, sigoden/llm-functions, sigoden/argc
# 需求: 1.1, 1.2, 2.1, 2.4, 1.4, 3.4

# ============================================================
# Agent Framework Communication Interface
# ============================================================


request_ai_processing() {
    local request_json="$1"
    local timeout_seconds="${2:-30}"
    
    # Validate request format
    local validation_result
    validation_result=$(validate_ai_request "$request_json")
    
    if [[ "$validation_result" == VALIDATION_ERROR:* ]]; then
        local error_msg="${validation_result#VALIDATION_ERROR: }"
        create_error_response "Request validation failed: $error_msg" "true"
        return 1
    fi
    
    # Parse request type from JSON
    local request_type
    request_type=$(extract_json_field "$request_json" "type")
    
    if [[ -z "$request_type" ]]; then
        create_error_response "Invalid request format - missing type" "true"
        return 1
    fi
    
    # Route to appropriate handler based on request type
    case "$request_type" in
        "command_generation")
            _handle_command_generation_request "$request_json" "$timeout_seconds"
            ;;
        "result_analysis")
            _handle_result_analysis_request "$request_json" "$timeout_seconds"
            ;;
        "data_analysis")
            _handle_data_analysis_request "$request_json" "$timeout_seconds"
            ;;
        *)
            create_error_response "Unknown request type: $request_type" "true"
            return 1
            ;;
    esac
}

# Handle command generation requests
_handle_command_generation_request() {
    local request_json="$1"
    local timeout_seconds="${2:-30}"
    
    # Extract parameters from JSON
    local intent device_type target
    intent=$(extract_json_field "$request_json" "intent")
    target=$(extract_json_field "$request_json" "target")
    device_type=$(extract_json_field "$request_json" "device_type")
    
    # Validate required parameters
    if [[ -z "$intent" || -z "$target" ]]; then
        create_error_response "Missing required parameters for command generation" "true"
        return 1
    fi
    [[ -z "$device_type" ]] && device_type="unknown"
    
    # Validate intent safety
    validate_intent "$intent"
    local intent_validation=$?
    if [[ $intent_validation -eq 1 ]]; then
        create_error_response "Invalid intent format" "true"
        return 1
    elif [[ $intent_validation -eq 2 ]]; then
        create_error_response "Potentially dangerous intent detected" "false"
        return 1
    fi
    
    # Validate device type if provided (unknown treated as skip)
    if [[ -n "$device_type" && "$device_type" != "unknown" ]]; then
        if ! validate_device_type "$device_type"; then
            create_error_response "Invalid device type: $device_type" "true"
            return 1
        fi
    fi
    
    local rule_result
    if rule_result=$(_generate_rule_based_command "$intent" "$device_type" "$target"); then
        local escaped_command
        escaped_command=$(sanitize_json_string "$rule_result")
        local response="{\"command\": \"$escaped_command\", \"confidence\": 0.6, \"fallback_used\": true, \"safety_check\": {\"is_dangerous\": false, \"warnings\": []}, \"metadata\": {\"generation_method\": \"rules\", \"device_specific\": $( [[ "$device_type" != "unknown" ]] && echo true || echo false )}}"
        echo "$response"
        return 0
    else
        create_error_response "Failed to generate command" "false"
        return 1
    fi
}

# Handle result analysis requests
_handle_result_analysis_request() {
    local request_json="$1"
    local timeout_seconds="${2:-30}"
    
    # Extract parameters from JSON
    local intent data context
    intent=$(extract_json_field "$request_json" "intent")
    data=$(extract_json_field "$request_json" "data")
    context=$(echo "$request_json" | grep -o '"context":{[^}]*}' | cut -d'{' -f2 | cut -d'}' -f1)
    
    # Validate required parameters
    if [[ -z "$intent" || -z "$data" ]]; then
        create_error_response "Missing required parameters for result analysis" "true"
        return 1
    fi
    
    # Validate intent
    if ! validate_intent "$intent" >/dev/null; then
        create_error_response "Invalid intent format" "true"
        return 1
    fi
    
    # Validate data size (prevent extremely large data)
    if [[ ${#data} -gt 100000 ]]; then
        create_error_response "Data size too large for analysis" "true"
        return 1
    fi
    
    local rule_result
    if rule_result=$(_generate_rule_based_analysis "$intent" "$data" "$context"); then
        local escaped_analysis
        escaped_analysis=$(sanitize_json_string "$rule_result")
        
        local response="{\"analysis\": \"$escaped_analysis\", \"summary\": \"Rule-based analysis\", \"issues\": [], \"recommendations\": [], \"next_actions\": [], \"confidence\": 0.6, \"metadata\": {\"analysis_method\": \"rules\", \"data_quality\": \"good\"}}"
        echo "$response"
        return 0
    else
        create_error_response "Failed to analyze data" "false"
        return 1
    fi
}

# Handle data analysis requests
_handle_data_analysis_request() {
    local request_json="$1"
    local timeout_seconds="${2:-30}"
    
    # Extract parameters from JSON
    local intent data analysis_type
    intent=$(extract_json_field "$request_json" "intent")
    data=$(extract_json_field "$request_json" "data")
    analysis_type=$(extract_json_field "$request_json" "analysis_type")
    
    # Validate required parameters
    if [[ -z "$intent" || -z "$data" || -z "$analysis_type" ]]; then
        create_error_response "Missing required parameters for data analysis" "true"
        return 1
    fi
    
    # Validate intent
    if ! validate_intent "$intent" >/dev/null; then
        create_error_response "Invalid intent format" "true"
        return 1
    fi
    
    # Validate data size
    if [[ ${#data} -gt 100000 ]]; then
        create_error_response "Data size too large for analysis" "true"
        return 1
    fi
    
    # Validate analysis type
    local valid_analysis_types=("ssh" "file" "log" "performance" "security" "network" "system")
    local valid_type=false
    for valid in "${valid_analysis_types[@]}"; do
        if [[ "$analysis_type" == "$valid" ]]; then
            valid_type=true
            break
        fi
    done
    
    if [[ "$valid_type" == false ]]; then
        create_error_response "Invalid analysis type: $analysis_type" "true"
        return 1
    fi
    
    local rule_result
    if rule_result=$(_generate_rule_based_data_analysis "$intent" "$data" "$analysis_type"); then
        local escaped_analysis
        escaped_analysis=$(sanitize_json_string "$rule_result")
        
        local response="{\"analysis\": \"$escaped_analysis\", \"summary\": \"Rule-based data analysis\", \"issues\": [], \"recommendations\": [], \"next_actions\": [], \"confidence\": 0.6, \"metadata\": {\"analysis_method\": \"rules\", \"data_quality\": \"good\"}}"
        echo "$response"
        return 0
    else
        create_error_response "Failed to analyze data" "false"
        return 1
    fi
}

# AI-enhanced command generation (leverages agent framework and RAG)
_generate_ai_enhanced_command() {
    local intent="$1"
    local device_type="$2"
    local target="$3"
    local timeout_seconds="${4:-30}"
    
    # 检查是否在 agent 模式下运行（通过 $LLM_OUTPUT 检测）
    # 在 agent 模式下，不应该再次调用 aichat，直接返回失败以触发 rule-based fallback
    if [[ -n "${LLM_OUTPUT:-}" ]]; then
        # 在 agent 上下文中，工具函数不应该再次调用 LLM
        # 返回失败，让调用者使用 rule-based fallback
        return 1
    fi
    
    # 非 agent 模式：可以尝试调用 aichat（用于独立调用场景）
    # 注意：不使用 session，避免历史污染
    
    # 实现超时机制
    local temp_file="/tmp/ai_command_$$"
    (
        request_ai_command_generation "$intent" "$device_type" "$target" > "$temp_file" 2>&1
        echo $? > "${temp_file}.exit"
    ) &
    local bg_pid=$!
    
    # 等待完成或超时
    local elapsed=0
    while [[ $elapsed -lt $timeout_seconds ]] && kill -0 $bg_pid 2>/dev/null; do
        sleep 1
        ((elapsed++))
    done
    
    if kill -0 $bg_pid 2>/dev/null; then
        # 进程仍在运行，终止它
        kill $bg_pid 2>/dev/null
        rm -f "$temp_file" "${temp_file}.exit"
        return 1
    fi
    
    # 检查命令是否成功完成
    if [[ -f "${temp_file}.exit" ]] && [[ $(cat "${temp_file}.exit") -eq 0 ]] && [[ -f "$temp_file" ]]; then
        cat "$temp_file"
        rm -f "$temp_file" "${temp_file}.exit"
        return 0
    else
        rm -f "$temp_file" "${temp_file}.exit"
        return 1
    fi
}

# AI-enhanced analysis (leverages agent framework and RAG)
_generate_ai_enhanced_analysis() {
    local intent="$1"
    local data="$2"
    local context="$3"
    local timeout_seconds="${4:-30}"
    
    # 检查是否在 agent 模式下运行（通过 $LLM_OUTPUT 检测）
    # 在 agent 模式下，不应该再次调用 aichat，直接返回失败以触发 rule-based fallback
    if [[ -n "${LLM_OUTPUT:-}" ]]; then
        # 在 agent 上下文中，工具函数不应该再次调用 LLM
        # 返回失败，让调用者使用 rule-based fallback
        return 1
    fi
    
    # 非 agent 模式：可以尝试调用 aichat（用于独立调用场景）
    # 注意：不使用 session，避免历史污染
    # 从上下文中提取命令和设备信息（如果可用）
    local command device_type target
    command=$(echo "$context" | grep -o '"command":"[^"]*"' | cut -d'"' -f4)
    device_type=$(echo "$context" | grep -o '"device_type":"[^"]*"' | cut -d'"' -f4)
    target=$(echo "$context" | grep -o '"target":"[^"]*"' | cut -d'"' -f4)
    
    # 实现超时机制
    local temp_file="/tmp/ai_analysis_$$"
    (
        request_ai_result_analysis "$intent" "${command:-unknown}" "$data" "${device_type:-unknown}" "${target:-unknown}" > "$temp_file" 2>&1
        echo $? > "${temp_file}.exit"
    ) &
    local bg_pid=$!
    
    # 等待完成或超时
    local elapsed=0
    while [[ $elapsed -lt $timeout_seconds ]] && kill -0 $bg_pid 2>/dev/null; do
        sleep 1
        ((elapsed++))
    done
    
    if kill -0 $bg_pid 2>/dev/null; then
        # 进程仍在运行，终止它
        kill $bg_pid 2>/dev/null
        rm -f "$temp_file" "${temp_file}.exit"
        return 1
    fi
    
    # 检查分析是否成功完成
    if [[ -f "${temp_file}.exit" ]] && [[ $(cat "${temp_file}.exit") -eq 0 ]] && [[ -f "$temp_file" ]]; then
        cat "$temp_file"
        rm -f "$temp_file" "${temp_file}.exit"
        return 0
    else
        rm -f "$temp_file" "${temp_file}.exit"
        return 1
    fi
}

# AI-enhanced data analysis (leverages agent framework and RAG)
_generate_ai_enhanced_data_analysis() {
    local intent="$1"
    local data="$2"
    local analysis_type="$3"
    local timeout_seconds="${4:-30}"
    
    # 检查是否在 agent 模式下运行（通过 $LLM_OUTPUT 检测）
    # 在 agent 模式下，不应该再次调用 aichat，直接返回失败以触发 rule-based fallback
    if [[ -n "${LLM_OUTPUT:-}" ]]; then
        # 在 agent 上下文中，工具函数不应该再次调用 LLM
        # 返回失败，让调用者使用 rule-based fallback
        return 1
    fi
    
    # 非 agent 模式：可以尝试调用 aichat（用于独立调用场景）
    # 注意：不使用 session，避免历史污染
    
    # 实现超时机制
    local temp_file="/tmp/ai_data_analysis_$$"
    (
        request_ai_data_analysis "$intent" "$data" "$analysis_type" > "$temp_file" 2>&1
        echo $? > "${temp_file}.exit"
    ) &
    local bg_pid=$!
    
    # 等待完成或超时
    local elapsed=0
    while [[ $elapsed -lt $timeout_seconds ]] && kill -0 $bg_pid 2>/dev/null; do
        sleep 1
        ((elapsed++))
    done
    
    if kill -0 $bg_pid 2>/dev/null; then
        # 进程仍在运行，终止它
        kill $bg_pid 2>/dev/null
        rm -f "$temp_file" "${temp_file}.exit"
        return 1
    fi
    
    # 检查数据分析是否成功完成
    if [[ -f "${temp_file}.exit" ]] && [[ $(cat "${temp_file}.exit") -eq 0 ]] && [[ -f "$temp_file" ]]; then
        cat "$temp_file"
        rm -f "$temp_file" "${temp_file}.exit"
        return 0
    else
        rm -f "$temp_file" "${temp_file}.exit"
        return 1
    fi
}

# 生成唯一 request_id
_generate_request_id() {
    echo "$(date +%s)-$RANDOM-$$"
}

# 生成 timestamp
_generate_timestamp() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# ============================================================
# AI 命令生成请求 (内部函数，不暴露为 agent 工具)
# ============================================================
# 注意：此函数是内部实现，不应被 LLM 直接调用
# 用户应通过 ssh_ai 等高级接口使用
request_ai_command_generation() {
    local intent="$1"
    local device_type="$2"
    local target="$3"
    
    # 验证必需参数
    if [[ -z "$intent" || -z "$device_type" || -z "$target" ]]; then
        echo "Error: Missing required parameters" >&2
        return 1
    fi
    
    # 检查是否在 agent 模式下运行（通过 $LLM_OUTPUT 检测）
    if [[ -n "${LLM_OUTPUT:-}" ]]; then
        # 在 agent 模式下，不应该再次调用 aichat
        # 这会导致嵌套 LLM 调用和 session 历史污染
        echo "Error: Cannot call aichat from within agent context. Use rule-based fallback instead." >&2
        return 1
    fi
    
    # 非 agent 模式：检查 aichat 可用性（用于独立调用）
    if ! command -v aichat >/dev/null 2>&1; then
        echo "Error: aichat not found. Please install sigoden/aichat" >&2
        return 1
    fi
    
    # 构建设备特定的提示
    local device_context
    case "$device_type" in
        "linux")
            device_context="这是一个 Linux 系统。使用标准的 Linux 命令，如 ps, top, df, free, netstat, systemctl 等。"
            ;;
        "openwrt")
            device_context="这是一个 OpenWrt 路由器系统。使用 OpenWrt 特有的命令，如 uci, opkg, logread, wifi 等。避免使用 systemctl。"
            ;;
        "cisco")
            device_context="这是一个 Cisco 网络设备。使用 Cisco IOS 命令，如 show running-config, show ip route, show interface 等。"
            ;;
        "huawei")
            device_context="这是一个华为网络设备。使用华为 VRP 命令，如 display current-configuration, display ip routing-table 等。"
            ;;
        *)
            device_context="这是一个 $device_type 设备。请根据设备类型使用合适的命令。"
            ;;
    esac
    
    # 构建完整的提示
    local prompt="你是一个专业的系统管理员助手。根据用户意图和设备类型，生成准确的命令。

设备信息：
- 目标: $target
- 设备类型: $device_type
- 设备说明: $device_context

用户意图: $intent

要求：
1. 只返回可执行的命令，不要解释
2. 命令必须适合 $device_type 设备
3. 避免危险操作（删除、重启、格式化等）
4. 如果需要多个命令，用 && 连接
5. 不要使用 Markdown 格式
6. 不要添加 $ 或 # 提示符

请直接返回命令："
    
    # 调用 aichat（仅在非 agent 模式下，不使用 session）
    # 原则：LLM 层必须无记忆，避免历史污染和幻觉
    local result
    if result=$(echo "$prompt" | aichat 2>/dev/null); then
        # 清理输出
        echo "$result" | sed '/^```/d' | sed 's/^bash:[[:space:]]*//' | sed 's/^sh:[[:space:]]*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
        return 0
    else
        echo "Error: Failed to get AI response" >&2
        return 1
    fi
}

# ============================================================
# AI 结果分析请求 (内部函数，不暴露为 agent 工具)
# ============================================================
# 注意：此函数是内部实现，不应被 LLM 直接调用
# 用户应通过 ssh_analy 等高级接口使用
request_ai_result_analysis() {
    local intent="$1"
    local command="$2"
    local output="$3"
    local device_type="${4:-unknown}"
    local target="${5:-unknown}"
    
    # 验证必需参数
    if [[ -z "$intent" || -z "$command" || -z "$output" ]]; then
        echo "Error: Missing required parameters" >&2
        return 1
    fi
    
    # 检查是否在 agent 模式下运行（通过 $LLM_OUTPUT 检测）
    if [[ -n "${LLM_OUTPUT:-}" ]]; then
        # 在 agent 模式下，不应该再次调用 aichat
        # 这会导致嵌套 LLM 调用和 session 历史污染
        echo "Error: Cannot call aichat from within agent context. Use rule-based fallback instead." >&2
        return 1
    fi
    
    # 非 agent 模式：检查 aichat 可用性（用于独立调用）
    if ! command -v aichat >/dev/null 2>&1; then
        echo "Error: aichat not found. Please install sigoden/aichat" >&2
        return 1
    fi
    
    # 构建分析提示
    local prompt="请分析以下命令执行结果，提供专业的分析和建议。

设备信息：
- 目标: $target
- 设备类型: $device_type
- 执行意图: $intent
- 执行命令: $command

执行结果：
$output

请从以下四个维度进行分析：
1. 结果分析：解释执行结果的含义
2. 问题识别：识别可能存在的问题或异常
3. 优化建议：提供性能或配置优化建议
4. 后续操作：建议下一步可能需要的操作

请使用 Markdown 格式，结构化输出分析结果。"
    
    # 调用 aichat（仅在非 agent 模式下，不使用 session）
    # 原则：LLM 层必须无记忆，避免历史污染和幻觉
    local result
    if result=$(echo "$prompt" | aichat 2>/dev/null); then
        echo "$result"
        return 0
    else
        echo "Error: Failed to get AI analysis" >&2
        return 1
    fi
}

# ============================================================
# AI 数据分析请求 (内部函数，不暴露为 agent 工具)
# ============================================================
# 注意：此函数是内部实现，不应被 LLM 直接调用
# 用户应通过 ssh_analy 等高级接口使用
request_ai_data_analysis() {
    local intent="$1"
    local data="$2"
    local analysis_type="$3"
    
    # 验证必需参数
    if [[ -z "$intent" || -z "$data" || -z "$analysis_type" ]]; then
        echo "Error: Missing required parameters" >&2
        return 1
    fi
    
    # 检查是否在 agent 模式下运行（通过 $LLM_OUTPUT 检测）
    if [[ -n "${LLM_OUTPUT:-}" ]]; then
        # 在 agent 模式下，不应该再次调用 aichat
        # 这会导致嵌套 LLM 调用和 session 历史污染
        echo "Error: Cannot call aichat from within agent context. Use rule-based fallback instead." >&2
        return 1
    fi
    
    # 非 agent 模式：检查 aichat 可用性（用于独立调用）
    if ! command -v aichat >/dev/null 2>&1; then
        echo "Error: aichat not found. Please install sigoden/aichat" >&2
        return 1
    fi
    
    # 构建分析提示
    local prompt="请对以下数据进行专业分析。

分析意图: $intent
数据类型: $analysis_type

数据内容:
$data

请提供：
1. 数据概览和关键指标
2. 异常或问题识别
3. 趋势分析（如适用）
4. 建议和后续行动

请使用 Markdown 格式输出分析结果。"
    
    # 调用 aichat（仅在非 agent 模式下，不使用 session）
    # 原则：LLM 层必须无记忆，避免历史污染和幻觉
    local result
    if result=$(echo "$prompt" | aichat 2>/dev/null); then
        echo "$result"
        return 0
    else
        echo "Error: Failed to get AI data analysis" >&2
        return 1
    fi
}

# ============================================================
# 检查框架依赖
# ============================================================
check_framework_dependencies() {
    local missing_deps=()
    local warnings=()
    
    # 检查 aichat (必需)
    if ! command -v aichat >/dev/null 2>&1; then
        missing_deps+=("aichat (sigoden/aichat)")
    fi
    
    # 检查 argc (推荐)
    if ! command -v argc >/dev/null 2>&1; then
        warnings+=("argc (sigoden/argc) - recommended for better CLI parsing")
    fi
    
    # 检查基础工具
    for tool in date grep cut sed tr; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done
    
    # 输出结果
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies:" >&2
        printf "  - %s\n" "${missing_deps[@]}" >&2
        echo "" >&2
        echo "Please install:" >&2
        echo "  - aichat: cargo install aichat" >&2
        echo "  - argc: cargo install argc" >&2
        return 1
    fi
    
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo "Warning: Missing recommended dependencies:" >&2
        printf "  - %s\n" "${warnings[@]}" >&2
        echo "" >&2
    fi
    
    return 0
}

# ============================================================
# 注意：不再使用 aichat session
# ============================================================
# 原则：LLM 层必须无记忆（防止幻觉）
# - LLM 不允许用 session 历史，因为旧的意图会污染函数选择
# - LLM 会幻想"还连着之前的主机"
# - 会重复旧命令，产生错误的自动工具选择
# 
# SH-AI 层：必须保留状态（否则功能损坏）
# - SH-AI 使用 ControlMaster 保持 SSH 连接
# - 有自己的缓存模块：cache.sh
# - 有自己的状态系统：ssh_core.sh
# - ~/.config/aichat/functions/cache/sh-ai/ 记录：
#   * last_target
#   * control socket path
#   * device type
#   * connection status
# 
# 这些与 LLM 没有关系，是 SH-AI 自主维护的本地状态

# ============================================================
# 清理 AI 命令输出
# ============================================================
clean_ai_command_output() {
    local ai_output="$1"
    
    # 移除 Markdown 代码块标记
    ai_output=$(echo "$ai_output" | sed '/^```/d')
    
    # 移除命令前缀 (bash:, sh:, 等)
    ai_output=$(echo "$ai_output" | sed 's/^bash:[[:space:]]*//' | sed 's/^sh:[[:space:]]*//')
    
    # 移除前导和尾随空格
    ai_output=$(echo "$ai_output" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    # 移除 $ 提示符
    ai_output=$(echo "$ai_output" | sed 's/^[$#][[:space:]]*//')
    
    echo "$ai_output"
}

# ============================================================
# Rule-based Fallback Functions
# ============================================================

# Rule-based command generation fallback
_generate_rule_based_command() {
    local intent="$1"
    local device_type="$2"
    local target="$3"
    
    # Convert intent to lowercase for matching
    local intent_lower
    intent_lower=$(echo "$intent" | tr '[:upper:]' '[:lower:]')
    
    # Device-specific command mapping
    case "$device_type" in
        "linux")
            case "$intent_lower" in
                *"memory"*|*"ram"*) echo "free -h" ;;
                *"disk"*|*"storage"*|*"space"*) echo "df -h" ;;
                *"process"*|*"cpu"*) echo "top -bn1" ;;
                *"network"*|*"interface"*) echo "ip addr show" ;;
                *"system"*|*"info"*) echo "uname -a" ;;
                *"uptime"*) echo "uptime" ;;
                *"load"*) echo "uptime && free -h" ;;
                *) echo "echo 'Unknown intent for Linux: $intent'" ;;
            esac
            ;;
        "openwrt")
            case "$intent_lower" in
                *"memory"*|*"ram"*) echo "cat /proc/meminfo | head -5" ;;
                *"disk"*|*"storage"*|*"space"*) echo "df -h" ;;
                *"process"*|*"cpu"*) echo "top -bn1" ;;
                *"network"*|*"interface"*) echo "ip addr show" ;;
                *"system"*|*"info"*) echo "cat /etc/openwrt_release" ;;
                *"uptime"*) echo "uptime" ;;
                *"wifi"*|*"wireless"*) echo "iwinfo" ;;
                *"config"*) echo "uci show" ;;
                *) echo "echo 'Unknown intent for OpenWrt: $intent'" ;;
            esac
            ;;
        "cisco")
            case "$intent_lower" in
                *"interface"*|*"network"*) echo "show ip interface brief" ;;
                *"config"*) echo "show running-config" ;;
                *"version"*|*"system"*) echo "show version" ;;
                *"route"*|*"routing"*) echo "show ip route" ;;
                *"memory"*) echo "show memory" ;;
                *"process"*|*"cpu"*) echo "show processes cpu" ;;
                *) echo "show version" ;;
            esac
            ;;
        "huawei")
            case "$intent_lower" in
                *"interface"*|*"network"*) echo "display ip interface brief" ;;
                *"config"*) echo "display current-configuration" ;;
                *"version"*|*"system"*) echo "display version" ;;
                *"route"*|*"routing"*) echo "display ip routing-table" ;;
                *"memory"*) echo "display memory" ;;
                *"process"*|*"cpu"*) echo "display cpu-usage" ;;
                *) echo "display version" ;;
            esac
            ;;
        *)
            # Generic fallback
            case "$intent_lower" in
                *"memory"*|*"ram"*) echo "free -h || cat /proc/meminfo" ;;
                *"disk"*|*"storage"*) echo "df -h" ;;
                *"process"*|*"cpu"*) echo "ps aux || top -bn1" ;;
                *"network"*) echo "ifconfig || ip addr" ;;
                *"system"*) echo "uname -a" ;;
                *) echo "echo 'Generic command for: $intent'" ;;
            esac
            ;;
    esac
}

# Rule-based result analysis fallback
_generate_rule_based_analysis() {
    local intent="$1"
    local data="$2"
    local context="$3"
    
    # Basic analysis based on common patterns
    local analysis="Rule-based Analysis\n\n"
    
    # Check for common error patterns
    if echo "$data" | grep -qi "error\|failed\|denied\|not found"; then
        analysis+="Status: Issues detected\n"
        analysis+="Issues: Command execution encountered errors\n"
    elif echo "$data" | grep -qi "permission denied\|access denied"; then
        analysis+="Status: Permission issues\n"
        analysis+="Issues: Insufficient permissions\n"
    else
        analysis+="Status: Command executed successfully\n"
    fi
    
    # Add basic recommendations based on intent
    local intent_lower
    intent_lower=$(echo "$intent" | tr '[:upper:]' '[:lower:]')
    
    case "$intent_lower" in
        *"memory"*|*"ram"*)
            analysis+="Recommendations: Monitor memory usage trends\n"
            ;;
        *"disk"*|*"storage"*)
            analysis+="Recommendations: Check for disk space issues\n"
            ;;
        *"network"*)
            analysis+="Recommendations: Verify network connectivity\n"
            ;;
        *)
            analysis+="Recommendations: Review output for anomalies\n"
            ;;
    esac
    
    echo -e "$analysis"
}

# Rule-based data analysis fallback
_generate_rule_based_data_analysis() {
    local intent="$1"
    local data="$2"
    local analysis_type="$3"
    
    local analysis="Rule-based Data Analysis\n\n"
    analysis+="Analysis Type: $analysis_type\n"
    analysis+="Intent: $intent\n\n"
    
    # Count lines and basic stats
    local line_count
    line_count=$(echo "$data" | wc -l)
    analysis+="Data Overview: $line_count lines of data\n\n"
    
    # Look for common patterns
    if echo "$data" | grep -qi "error\|fail\|exception"; then
        analysis+="Issues Found: Error patterns detected in data\n"
    fi
    
    if echo "$data" | grep -qi "warning\|warn"; then
        analysis+="Warnings: Warning messages found\n"
    fi
    
    analysis+="Recommendation: Manual review recommended for detailed analysis\n"
    
    echo -e "$analysis"
}

# ============================================================
# AI Request/Response Validation Functions
# ============================================================

# Validate AI request JSON format
validate_ai_request() {
    local request_json="$1"
    local errors=()
    
    # Check if request is not empty
    if [[ -z "$request_json" ]]; then
        errors+=("Request cannot be empty")
        echo "VALIDATION_ERROR: ${errors[*]}"
        return 1
    fi
    
    # Check for required type field
    if ! echo "$request_json" | grep -q '"type":[[:space:]]*"[^"]*"'; then
        errors+=("Missing required 'type' field")
    fi
    
    # Extract and validate request type
    local request_type
    request_type=$(echo "$request_json" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
    
    case "$request_type" in
        "command_generation")
            # Validate command generation request
            if ! echo "$request_json" | grep -q '"intent":[[:space:]]*"[^"]*"'; then
                errors+=("Missing required 'intent' field for command generation")
            fi
            if ! echo "$request_json" | grep -q '"device_type":[[:space:]]*"[^"]*"'; then
                errors+=("Missing required 'device_type' field for command generation")
            fi
            if ! echo "$request_json" | grep -q '"target":[[:space:]]*"[^"]*"'; then
                errors+=("Missing required 'target' field for command generation")
            fi
            ;;
        "result_analysis"|"data_analysis")
            # Validate analysis request
            if ! echo "$request_json" | grep -q '"intent":[[:space:]]*"[^"]*"'; then
                errors+=("Missing required 'intent' field for analysis")
            fi
            if ! echo "$request_json" | grep -q '"data":[[:space:]]*"[^"]*"'; then
                errors+=("Missing required 'data' field for analysis")
            fi
            ;;
        "")
            errors+=("Empty request type")
            ;;
        *)
            errors+=("Unknown request type: $request_type")
            ;;
    esac
    
    # Check JSON syntax (basic validation)
    if ! echo "$request_json" | grep -q '^{.*}$'; then
        errors+=("Invalid JSON format - must be enclosed in braces")
    fi
    
    # Return validation result
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "VALIDATION_ERROR: ${errors[*]}"
        return 1
    else
        echo "VALIDATION_SUCCESS"
        return 0
    fi
}

# Validate AI response JSON format
validate_ai_response() {
    local response_json="$1"
    local expected_type="${2:-any}"
    local errors=()
    
    # Check if response is not empty
    if [[ -z "$response_json" ]]; then
        errors+=("Response cannot be empty")
        echo "VALIDATION_ERROR: ${errors[*]}"
        return 1
    fi
    
    # Check for error responses
    if echo "$response_json" | grep -q '"error":[[:space:]]*true'; then
        # Error response should have message field
        if ! echo "$response_json" | grep -q '"message":[[:space:]]*"[^"]*"'; then
            errors+=("Error response missing 'message' field")
        fi
        # Error responses are valid if they have proper structure
        if [[ ${#errors[@]} -eq 0 ]]; then
            echo "VALIDATION_SUCCESS_ERROR"
            return 0
        fi
    fi
    
    # Validate successful response based on expected type
    case "$expected_type" in
        "command_generation")
            if ! echo "$response_json" | grep -q '"command":[[:space:]]*"[^"]*"'; then
                errors+=("Missing required 'command' field in command generation response")
            fi
            if ! echo "$response_json" | grep -q '"confidence":[[:space:]]*[0-9.]*'; then
                errors+=("Missing required 'confidence' field in command generation response")
            fi
            ;;
        "analysis")
            if ! echo "$response_json" | grep -q '"analysis":[[:space:]]*"[^"]*"'; then
                errors+=("Missing required 'analysis' field in analysis response")
            fi
            ;;
        "any")
            # Generic validation - just check it's valid JSON structure
            if ! echo "$response_json" | grep -q '^{.*}$'; then
                errors+=("Invalid JSON format")
            fi
            ;;
    esac
    
    # Return validation result
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "VALIDATION_ERROR: ${errors[*]}"
        return 1
    else
        echo "VALIDATION_SUCCESS"
        return 0
    fi
}

# Sanitize and escape JSON strings
sanitize_json_string() {
    local input="$1"
    
    # Escape special characters for JSON
    echo "$input" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\t/\\t/g' | sed 's/\n/\\n/g' | sed 's/\r/\\r/g'
}

# Extract field from JSON (simple extraction)
extract_json_field() {
    local json="$1"
    local field="$2"
    
    echo "$json" | grep -o "\"$field\":[[:space:]]*\"[^\"]*\"" | cut -d'"' -f4
}

# Create error response JSON
create_error_response() {
    local error_message="$1"
    local fallback_available="${2:-true}"
    
    local escaped_message
    escaped_message=$(sanitize_json_string "$error_message")
    
    echo "{\"error\": true, \"message\": \"$escaped_message\", \"fallback_available\": $fallback_available}"
}

# Timeout handler for AI requests
handle_ai_request_timeout() {
    local timeout_seconds="${1:-30}"
    local request_description="${2:-AI request}"
    
    # This function can be used to implement timeout logic
    echo "TIMEOUT: $request_description exceeded $timeout_seconds seconds"
    create_error_response "Request timeout after $timeout_seconds seconds" "true"
}

# Validate device type (使用 device_detect.sh 中的宽松验证)
validate_device_type() {
    local device_type="$1"
    
    # 调用 device_detect.sh 中的 _validate_device_type 函数
    # 这个函数支持任意合法的设备类型
    _validate_device_type "$device_type"
}

# Validate intent string
validate_intent() {
    local intent="$1"
    
    # Check intent is not empty and has reasonable length
    if [[ -z "$intent" ]]; then
        return 1
    fi
    
    if [[ ${#intent} -gt 500 ]]; then
        return 1  # Intent too long
    fi
    
    # Check for potentially dangerous commands in intent
    if echo "$intent" | grep -qi -E "(rm -rf|format|mkfs|dd if=|shutdown|reboot|halt|init 0|init 6)"; then
        return 2  # Potentially dangerous intent
    fi
    
    return 0
}

# Check if running in agent framework context
is_agent_framework_available() {
    [[ -n "${LLM_FUNCTIONS_AGENT_MODE:-}" ]] || [[ -n "${LLM_OUTPUT:-}" ]] || command -v aichat >/dev/null 2>&1
}

# 导出核心函数
export -f request_ai_processing request_ai_command_generation request_ai_result_analysis request_ai_data_analysis
export -f check_framework_dependencies clean_ai_command_output
export -f _generate_request_id _generate_timestamp is_agent_framework_available
export -f _generate_rule_based_command _generate_rule_based_analysis _generate_rule_based_data_analysis
export -f validate_ai_request validate_ai_response sanitize_json_string extract_json_field create_error_response
export -f handle_ai_request_timeout validate_device_type validate_intent