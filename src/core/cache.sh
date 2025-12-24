#!/usr/bin/env bash

# ============================================================
# SH-AI 缓存管理核心模块
# ============================================================
# 职责: 设备类型识别结果的缓存管理
# 需求: 5.3, 5.4, 5.5

# 缓存配置常量
readonly SH_AI_CACHE_DIR="${SH_AI_CACHE_DIR:-$HOME/.cache/sh-ai/devices}"
readonly SH_AI_CACHE_EXPIRY="${SH_AI_CACHE_EXPIRY:-86400}"  # 24小时
readonly SH_AI_CACHE_MAX_SIZE="${SH_AI_CACHE_MAX_SIZE:-1000}"  # 最大缓存条目数
readonly CACHE_VERSION="1.0"

# 缓存性能统计
declare -g CACHE_HITS=0
declare -g CACHE_MISSES=0
declare -g CACHE_WRITES=0

# 确保缓存目录存在
_ensure_cache_dir() {
    if [[ ! -d "$SH_AI_CACHE_DIR" ]]; then
        mkdir -p "$SH_AI_CACHE_DIR"
        chmod 700 "$SH_AI_CACHE_DIR"
    fi
}

# 生成缓存键 (基于目标主机的 MD5)
_generate_cache_key() {
    local target="$1"
    echo -n "$target" | md5sum | cut -d' ' -f1
}

# 获取缓存文件路径
_get_cache_file() {
    local target="$1"
    local cache_key
    cache_key=$(_generate_cache_key "$target")
    echo "$SH_AI_CACHE_DIR/device-$cache_key.cache"
}

# 保存设备类型缓存 (性能优化版本)
_save_device_cache() {
    local target="$1"
    local device_type="$2"
    local detection_method="${3:-manual}"
    local cache_file
    
    _ensure_cache_dir
    cache_file=$(_get_cache_file "$target")
    
    # 管理缓存大小
    _manage_cache_size
    
    local timestamp
    timestamp=$(date +%s)
    
    # 缓存格式: device_type:timestamp:method:version:target
    local cache_content="${device_type}:${timestamp}:${detection_method}:${CACHE_VERSION}:${target}"
    
    # 使用原子写入避免并发问题
    local temp_file="${cache_file}.tmp.$$"
    
    if echo "$cache_content" > "$temp_file" && mv "$temp_file" "$cache_file"; then
        ((CACHE_WRITES++))
        _debug "设备类型缓存已保存: $target -> $device_type (方法: $detection_method)"
        return 0
    else
        rm -f "$temp_file" 2>/dev/null
        _error "缓存保存失败: $cache_file"
        return 1
    fi
}

# 加载设备类型缓存 (性能优化版本)
_load_device_cache() {
    local target="$1"
    local cache_file
    cache_file=$(_get_cache_file "$target")
    
    # 快速检查文件是否存在且可读
    if [[ ! -f "$cache_file" || ! -r "$cache_file" ]]; then
        ((CACHE_MISSES++))
        return 1
    fi
    
    # 读取缓存文件内容
    local cache_content
    if ! cache_content=$(cat "$cache_file" 2>/dev/null); then
        ((CACHE_MISSES++))
        return 1
    fi
    
    # 快速验证内容不为空
    if [[ -z "$cache_content" ]]; then
        ((CACHE_MISSES++))
        rm -f "$cache_file" 2>/dev/null
        return 1
    fi
    
    # 解析缓存内容 (优化的解析方式)
    local IFS=':'
    local cache_parts=($cache_content)
    
    local device_type="${cache_parts[0]}"
    local timestamp="${cache_parts[1]}"
    local method="${cache_parts[2]}"
    local version="${cache_parts[3]}"
    local cached_target="${cache_parts[4]}"
    
    # 快速验证必要字段
    if [[ -z "$device_type" || -z "$timestamp" || -z "$version" ]]; then
        _debug "缓存格式无效: $cache_file"
        rm -f "$cache_file" 2>/dev/null
        ((CACHE_MISSES++))
        return 1
    fi
    
    # 检查版本兼容性
    if [[ "$version" != "$CACHE_VERSION" ]]; then
        _debug "缓存版本不兼容: $version != $CACHE_VERSION"
        rm -f "$cache_file" 2>/dev/null
        ((CACHE_MISSES++))
        return 1
    fi
    
    # 缓存命中
    ((CACHE_HITS++))
    
    # 输出缓存信息
    echo "device_type=$device_type"
    echo "timestamp=$timestamp"
    echo "method=$method"
    echo "version=$version"
    echo "target=$cached_target"
    
    return 0
}

# 检查缓存是否过期
_is_cache_expired() {
    local target="$1"
    local cache_info
    
    if ! cache_info=$(_load_device_cache "$target"); then
        return 0  # 缓存不存在，视为过期
    fi
    
    local timestamp
    timestamp=$(echo "$cache_info" | grep "^timestamp=" | cut -d'=' -f2)
    
    if [[ -z "$timestamp" ]]; then
        return 0  # 无效时间戳，视为过期
    fi
    
    local current_time
    current_time=$(date +%s)
    local age=$((current_time - timestamp))
    
    if [[ $age -gt $SH_AI_CACHE_EXPIRY ]]; then
        _debug "缓存已过期: $target (年龄: ${age}s, 限制: ${SH_AI_CACHE_EXPIRY}s)"
        return 0  # 过期
    else
        _debug "缓存仍有效: $target (年龄: ${age}s)"
        return 1  # 未过期
    fi
}

# 获取缓存的设备类型
_get_cached_device_type() {
    local target="$1"
    
    if _is_cache_expired "$target"; then
        return 1
    fi
    
    local cache_info
    if cache_info=$(_load_device_cache "$target"); then
        echo "$cache_info" | grep "^device_type=" | cut -d'=' -f2
        return 0
    else
        return 1
    fi
}

# 清除指定目标的缓存
_clear_device_cache() {
    local target="$1"
    local cache_file
    cache_file=$(_get_cache_file "$target")
    
    if [[ -f "$cache_file" ]]; then
        rm -f "$cache_file"
        _info "已清除设备缓存: $target"
        return 0
    else
        _warning "缓存文件不存在: $target"
        return 1
    fi
}

# 清理所有过期缓存
_cleanup_expired_cache() {
    _ensure_cache_dir
    
    local cleaned=0
    local total=0
    
    for cache_file in "$SH_AI_CACHE_DIR"/device-*.cache; do
        if [[ -f "$cache_file" ]]; then
            ((total++))
            
            local cache_content
            cache_content=$(cat "$cache_file" 2>/dev/null)
            
            if [[ -n "$cache_content" ]]; then
                IFS=':' read -r device_type timestamp method version target <<< "$cache_content"
                
                if [[ -n "$timestamp" ]]; then
                    local current_time
                    current_time=$(date +%s)
                    local age=$((current_time - timestamp))
                    
                    if [[ $age -gt $SH_AI_CACHE_EXPIRY ]]; then
                        rm -f "$cache_file"
                        ((cleaned++))
                        _debug "清理过期缓存: $target (年龄: ${age}s)"
                    fi
                else
                    # 无效格式，直接删除
                    rm -f "$cache_file"
                    ((cleaned++))
                    _debug "清理无效缓存: $cache_file"
                fi
            else
                # 空文件，直接删除
                rm -f "$cache_file"
                ((cleaned++))
                _debug "清理空缓存文件: $cache_file"
            fi
        fi
    done
    
    if [[ $cleaned -gt 0 ]]; then
        _info "清理了 $cleaned/$total 个过期缓存文件"
    else
        _debug "没有过期缓存需要清理 (总计: $total)"
    fi
    
    return 0
}

# 列出所有缓存条目
_list_cache_entries() {
    _ensure_cache_dir
    
    local entries=()
    
    for cache_file in "$SH_AI_CACHE_DIR"/device-*.cache; do
        if [[ -f "$cache_file" ]]; then
            local cache_content
            cache_content=$(cat "$cache_file" 2>/dev/null)
            
            if [[ -n "$cache_content" ]]; then
                IFS=':' read -r device_type timestamp method version target <<< "$cache_content"
                
                if [[ -n "$target" && -n "$device_type" && -n "$timestamp" ]]; then
                    local age
                    local current_time
                    current_time=$(date +%s)
                    age=$((current_time - timestamp))
                    
                    local status="valid"
                    if [[ $age -gt $SH_AI_CACHE_EXPIRY ]]; then
                        status="expired"
                    fi
                    
                    entries+=("$target:$device_type:$method:$age:$status")
                fi
            fi
        fi
    done
    
    printf '%s\n' "${entries[@]}"
}

# 获取缓存统计信息
_get_cache_stats() {
    _ensure_cache_dir
    
    local total=0
    local valid=0
    local expired=0
    local invalid=0
    
    for cache_file in "$SH_AI_CACHE_DIR"/device-*.cache; do
        if [[ -f "$cache_file" ]]; then
            ((total++))
            
            local cache_content
            cache_content=$(cat "$cache_file" 2>/dev/null)
            
            if [[ -n "$cache_content" ]]; then
                IFS=':' read -r device_type timestamp method version target <<< "$cache_content"
                
                if [[ -n "$timestamp" && -n "$device_type" ]]; then
                    local current_time
                    current_time=$(date +%s)
                    local age=$((current_time - timestamp))
                    
                    if [[ $age -gt $SH_AI_CACHE_EXPIRY ]]; then
                        ((expired++))
                    else
                        ((valid++))
                    fi
                else
                    ((invalid++))
                fi
            else
                ((invalid++))
            fi
        fi
    done
    
    echo "total=$total"
    echo "valid=$valid"
    echo "expired=$expired"
    echo "invalid=$invalid"
    echo "cache_dir=$SH_AI_CACHE_DIR"
    echo "expiry_seconds=$SH_AI_CACHE_EXPIRY"
}

# 管理缓存大小
_manage_cache_size() {
    _ensure_cache_dir
    
    local cache_count
    cache_count=$(find "$SH_AI_CACHE_DIR" -name "device-*.cache" -type f | wc -l)
    
    # 如果缓存数量超过限制，删除最旧的缓存
    if [[ $cache_count -gt $SH_AI_CACHE_MAX_SIZE ]]; then
        _debug "缓存数量超过限制 ($cache_count > $SH_AI_CACHE_MAX_SIZE)，清理最旧缓存"
        
        # 按修改时间排序，删除最旧的缓存文件
        local files_to_delete=$((cache_count - SH_AI_CACHE_MAX_SIZE + 10))  # 多删除10个，避免频繁清理
        
        find "$SH_AI_CACHE_DIR" -name "device-*.cache" -type f -printf '%T@ %p\n' | \
        sort -n | head -n "$files_to_delete" | cut -d' ' -f2- | \
        xargs -r rm -f
        
        _debug "已清理 $files_to_delete 个旧缓存文件"
    fi
}

# 获取缓存性能统计
_get_cache_performance_stats() {
    local total_requests=$((CACHE_HITS + CACHE_MISSES))
    local hit_rate=0
    
    if [[ $total_requests -gt 0 ]]; then
        hit_rate=$((CACHE_HITS * 100 / total_requests))
    fi
    
    echo "cache_hits=$CACHE_HITS"
    echo "cache_misses=$CACHE_MISSES"
    echo "cache_writes=$CACHE_WRITES"
    echo "total_requests=$total_requests"
    echo "hit_rate=${hit_rate}%"
}

# 预热缓存 (批量加载常用缓存)
_warm_cache() {
    _ensure_cache_dir
    
    # 异步预热最近使用的缓存
    (
        find "$SH_AI_CACHE_DIR" -name "device-*.cache" -type f -mtime -1 | \
        head -20 | \
        while read -r cache_file; do
            # 简单读取文件到内存，利用系统缓存
            cat "$cache_file" >/dev/null 2>&1
        done
    ) &
}

# 缓存模块初始化 (性能优化版本)
_cache_init() {
    _ensure_cache_dir
    
    # 异步清理过期缓存 (不阻塞主流程)
    (_cleanup_expired_cache &)
    
    # 管理缓存大小
    _manage_cache_size
    
    # 预热缓存
    _warm_cache
    
    _debug "缓存模块初始化完成"
}

# 保存最后连接的目标
_save_last_connected_target() {
    local target="$1"
    _ensure_cache_dir
    
    local cache_file="$SH_AI_CACHE_DIR/last_connected_target"
    local timestamp
    timestamp=$(date +%s)
    
    # 格式: target:timestamp
    local cache_content="${target}:${timestamp}"
    
    if echo "$cache_content" > "$cache_file"; then
        _debug "最后连接目标已保存: $target"
        return 0
    else
        _error "保存最后连接目标失败"
        return 1
    fi
}

# 获取最后连接的目标
# 优先从 last_connected_target 文件读取，如果不存在则从 connection_registry 获取最新的连接
_get_last_connected_target() {
    _ensure_cache_dir
    
    # 方法1：从专用缓存文件读取
    local cache_file="$SH_AI_CACHE_DIR/last_connected_target"
    if [[ -f "$cache_file" ]]; then
        local cache_content
        if cache_content=$(cat "$cache_file" 2>/dev/null); then
            if [[ -n "$cache_content" ]]; then
                # 解析: target:timestamp
                # 注意：target 可能包含端口号（如 root@host:22），所以只取最后一个 : 之前的部分作为 target
                local target="${cache_content%:*}"
                if [[ -n "$target" ]]; then
                    echo "$target"
                    return 0
                fi
            fi
        fi
    fi
    
    # 方法2：从 connection_registry 获取最新的连接（回退方案）
    local registry_file="$SSH_CONTROL_DIR/connection_registry"
    if [[ -f "$registry_file" ]]; then
        # 读取所有条目，找到时间戳最大的
        local max_timestamp=0
        local latest_target=""
        
        while IFS=':' read -r connection_id rest; do
            if [[ -z "$connection_id" || -z "$rest" ]]; then
                continue
            fi
            
            # 时间戳是最后一个字段
            local timestamp="${rest##*:}"
            # target 是去掉 connection_id 和 timestamp 后的部分
            local target="${rest%:*}"
            
            # 比较时间戳
            if [[ "$timestamp" =~ ^[0-9]+$ ]] && [[ $timestamp -gt $max_timestamp ]]; then
                max_timestamp=$timestamp
                latest_target="$target"
            fi
        done < "$registry_file"
        
        if [[ -n "$latest_target" ]]; then
            echo "$latest_target"
            return 0
        fi
    fi
    
    return 1
}

# 导出核心函数
export -f _ensure_cache_dir _generate_cache_key _get_cache_file
export -f _save_device_cache _load_device_cache _is_cache_expired
export -f _get_cached_device_type _clear_device_cache _cleanup_expired_cache
export -f _list_cache_entries _get_cache_stats _cache_init
export -f _manage_cache_size _get_cache_performance_stats _warm_cache
export -f _save_last_connected_target _get_last_connected_target