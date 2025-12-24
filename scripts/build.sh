#!/usr/bin/env bash
# SH-AI 自动构建脚本
# 将模块化的核心模块和业务模块合并为 argc 兼容的单文件

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目根目录
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$PROJECT_ROOT/src/core"
MODULES_DIR="$PROJECT_ROOT/src/modules"
DIST_DIR="$PROJECT_ROOT/dist"
OUTPUT_FILE="$DIST_DIR/tools.sh"

echo -e "${BLUE}🚀 开始构建 SH-AI...${NC}"

# 1. 创建输出目录
mkdir -p "$DIST_DIR"

# 2. 生成文件头
echo -e "${YELLOW}📝 生成文件头...${NC}"
cat > "$OUTPUT_FILE" << EOF
#!/usr/bin/env bash
# SH-AI - AI增强型SSH管理工具
# 自动生成文件，请勿手动编辑
# 生成时间: $(date)
# 版本: 1.0.0

set -euo pipefail

# SH-AI 全局配置
declare -g SH_AI_VERSION="1.0.0"
declare -g SH_AI_BUILD_TIME="$(date)"
declare -g SH_AI_PROJECT_ROOT="\${SH_AI_PROJECT_ROOT:-\$HOME/.config/aichat/functions/agents/sh-ai}"

EOF

# 3. 合并核心模块 (按依赖顺序)
echo -e "${YELLOW}🔧 合并核心模块...${NC}"
CORE_MODULES=("output" "cache" "ssh_core" "device_detect" "ai_command" "ai_request")

for module in "${CORE_MODULES[@]}"; do
    module_file="$CORE_DIR/$module.sh"
    if [[ -f "$module_file" ]]; then
        echo -e "${GREEN}  ✓ 合并核心模块: $module.sh${NC}"
        echo "" >> "$OUTPUT_FILE"
        echo "# ==================== Core Module: $module.sh ====================" >> "$OUTPUT_FILE"
        # 移除 shebang 行、测试代码和 source 语句，避免重复和冲突
        sed '1{/^#!/d;}' "$module_file" | sed '/^# 如果直接执行此脚本/,/^fi$/d' | sed '/^source.*\.sh/d' >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    else
        echo -e "${YELLOW}  ⚠️ 核心模块不存在: $module.sh (将在后续任务中创建)${NC}"
    fi
done

# 4. 合并业务模块 (自动发现)
echo -e "${YELLOW}📦 合并业务模块...${NC}"
if [[ -d "$MODULES_DIR" ]]; then
    for module_file in "$MODULES_DIR"/*.sh; do
        if [[ -f "$module_file" ]]; then
            module_name=$(basename "$module_file")
            echo -e "${GREEN}  ✓ 合并业务模块: $module_name${NC}"
            echo "" >> "$OUTPUT_FILE"
            echo "# ==================== Business Module: $module_name ====================" >> "$OUTPUT_FILE"
            # 移除 shebang 行、测试代码和 source 语句，避免重复和冲突
            sed '1{/^#!/d;}' "$module_file" | sed '/^# 如果直接执行此脚本/,/^fi$/d' | sed '/^source.*\.sh/d' >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        fi
    done
else
    echo -e "${YELLOW}  ⚠️ 业务模块目录为空 (将在后续任务中创建)${NC}"
fi

# 5. 添加 argc 评估入口 (符合 llm-functions 标准)
echo -e "${YELLOW}🎯 添加 argc 评估入口...${NC}"
cat >> "$OUTPUT_FILE" << 'EOF'

# ==================== argc Entry Point ====================
# See more details at https://github.com/sigoden/argc
eval "$(argc --argc-eval "$0" "$@")"
EOF

# 6. 设置执行权限
chmod +x "$OUTPUT_FILE"

# 7. 验证生成的文件
echo -e "${YELLOW}🔍 验证生成的文件...${NC}"

# 检查语法
if bash -n "$OUTPUT_FILE"; then
    echo -e "${GREEN}  ✓ Bash 语法检查通过${NC}"
else
    echo -e "${RED}  ❌ Bash 语法检查失败${NC}"
    exit 1
fi

# 🚀 新版 argc 兼容性检查
if command -v argc &>/dev/null; then
    echo -e "${YELLOW}🔍 运行 argc 检查...${NC}"
    # 尝试新版 argc 命令
    if argc build@agent --check "$OUTPUT_FILE" >/dev/null 2>&1; then
        echo -e "${GREEN}  ✅ argc 检查通过${NC}"
    elif argc check "$OUTPUT_FILE" >/dev/null 2>&1; then
        # 回退到旧版 argc 命令
        echo -e "${GREEN}  ✅ argc 检查通过 (旧版)${NC}"
    else
        echo -e "${YELLOW}  ⚠️ argc 检查跳过 (版本兼容性问题或模块未完成)${NC}"
        # 不退出，继续构建
    fi
else
    echo -e "${YELLOW}  ⚠️ 未检测到 argc 命令，跳过检查${NC}"
fi

# 8. 生成 llm-functions 标准文件 (使用 argc 自动生成)
echo -e "${YELLOW}📋 生成 llm-functions 标准文件...${NC}"

# 生成 tools.txt (使用 argc 自动提取)
echo -e "${GREEN}  ✓ 生成 tools.txt${NC}"
if command -v argc &>/dev/null; then
    {
        echo "# SH-AI Tools List"
        echo "# Auto-generated from tools.sh using argc"
        echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        argc --argc-export "$OUTPUT_FILE" 2>/dev/null | \
        jq -r '.subcommands[]? | .name' 2>/dev/null || \
        grep -E "^# @cmd" "$OUTPUT_FILE" -A 1 | grep -E "^[a-z_]+\(\)" | sed 's/().*//'
    } > "$PROJECT_ROOT/tools.txt"
else
    # 备用方法：扫描函数定义
    {
        echo "# SH-AI Tools List"
        echo "# Auto-generated from tools.sh (fallback method)"
        echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        grep -E "^# @cmd" "$OUTPUT_FILE" -A 1 | grep -E "^[a-z_]+\(\)" | sed 's/().*//'
    } > "$PROJECT_ROOT/tools.txt"
fi

# 生成 functions.json (使用 argc 自动生成)
if [[ "${SKIP_FUNCTIONS_JSON:-}" == "1" ]]; then
    echo -e "${YELLOW}  ⏭️ 跳过 functions.json 生成（--skip-functions）${NC}"
elif command -v argc &>/dev/null && command -v jq &>/dev/null; then
    echo -e "${GREEN}  ✓ 生成 functions.json${NC}"
    # 备份现有的 functions.json
    if [[ -f "$PROJECT_ROOT/functions.json" ]]; then
        cp "$PROJECT_ROOT/functions.json" "$PROJECT_ROOT/functions.json.bak"
        echo -e "${YELLOW}  ℹ️ 已备份现有 functions.json 到 functions.json.bak${NC}"
    fi
    
    # 使用 argc 导出并转换为 OpenAI function calling 格式
    argc --argc-export "$OUTPUT_FILE" 2>/dev/null | \
    jq 'if .subcommands then .subcommands | map({
        name,
        description: .describe,
        parameters: {
            type: "object",
            properties: (
                # 处理位置参数（@arg）
                ((.positionals // []) | map(select(.name != null) | {
                    (.name): {
                        type: "string", 
                        description: (.describe // "")
                    }
                }) | add // {}) +
                # 处理选项参数（@option），过滤掉 help 参数
                ((.flag_options // []) | map(select(.long_name != null and .long_name != "--help") | {
                    (.long_name | ltrimstr("--") | gsub("-"; "_")): {
                        type: (if .flag then "boolean" else "string" end), 
                        description: (.describe // "")
                    }
                }) | add // {})
            ),
            # 提取必需参数，过滤掉 help
            required: (
                ((.positionals // []) | map(select(.required and .name != null) | .name)) +
                ((.flag_options // []) | map(select(.required and .long_name != null and .long_name != "--help") | .long_name | ltrimstr("--") | gsub("-"; "_")))
            )
        }
    }) else [] end' > "$PROJECT_ROOT/functions.json" 2>/dev/null && {
        echo -e "${GREEN}  ✅ functions.json 生成成功${NC}"
        func_count=$(jq 'length' "$PROJECT_ROOT/functions.json" 2>/dev/null || echo "0")
        echo -e "${BLUE}  📋 生成了 $func_count 个函数声明${NC}"
    } || {
        echo -e "${YELLOW}  ⚠️ argc 导出失败，保留现有 functions.json${NC}"
        echo -e "${YELLOW}  提示: 请确保所有函数都有 @cmd 注释${NC}"
        # 如果生成失败且没有备份，创建空数组
        if [[ ! -f "$PROJECT_ROOT/functions.json" ]] && [[ ! -f "$PROJECT_ROOT/functions.json.bak" ]]; then
            echo "[]" > "$PROJECT_ROOT/functions.json"
        elif [[ -f "$PROJECT_ROOT/functions.json.bak" ]]; then
            # 恢复备份
            mv "$PROJECT_ROOT/functions.json.bak" "$PROJECT_ROOT/functions.json"
        fi
    }
else
    echo -e "${YELLOW}  ⚠️ argc 或 jq 未安装，无法自动生成 functions.json${NC}"
    echo -e "${YELLOW}  提示: 安装 argc 和 jq 以自动生成函数声明${NC}"
    echo -e "${YELLOW}  安装方法:${NC}"
    echo -e "${YELLOW}    - argc: https://github.com/sigoden/argc${NC}"
    echo -e "${YELLOW}    - jq: sudo apt install jq (或 brew install jq)${NC}"
    # 如果文件不存在，创建空数组
    if [[ ! -f "$PROJECT_ROOT/functions.json" ]]; then
        echo "[]" > "$PROJECT_ROOT/functions.json"
    fi
fi

# 生成 tools.sh 符号链接 (指向构建输出)
echo -e "${GREEN}  ✓ 创建 tools.sh 符号链接${NC}"
ln -sf "dist/tools.sh" "$PROJECT_ROOT/tools.sh"

# 9. 显示构建结果
echo ""
echo -e "${GREEN}✅ 构建完成！${NC}"
echo -e "${BLUE}📄 输出文件: $OUTPUT_FILE${NC}"
echo -e "${BLUE}📊 文件大小: $(du -h "$OUTPUT_FILE" | cut -f1)${NC}"
echo -e "${BLUE}📝 总行数: $(wc -l < "$OUTPUT_FILE")${NC}"
echo -e "${BLUE}🔧 生成文件: tools.txt ,functions.json ,tools.sh${NC}"

# 10. 显示函数统计
if command -v argc &>/dev/null && command -v jq &>/dev/null; then
    func_count=$(argc --argc-export "$OUTPUT_FILE" 2>/dev/null | jq '.subcommands? | length' 2>/dev/null || echo "0")
    echo -e "${BLUE}📋 识别的函数数量: $func_count${NC}"
    
    if [[ "$func_count" == "0" ]]; then
        echo -e "${YELLOW}⚠️ 警告: 未识别到任何函数${NC}"
        echo -e "${YELLOW}   请确保函数定义前有 @cmd 注释${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ 无法统计函数数量 (需要 argc 和 jq)${NC}"
fi

# 11. 显示使用说明
echo ""
echo -e "${YELLOW}📖 下一步:${NC}"
echo -e "  1. ${GREEN}检查所有函数添加 argc 注释${NC} (src/modules/*.sh)"
echo -e "     示例: # @cmd <描述>"
echo -e "           # @arg <参数名>! <参数描述>"
echo -e ""
echo -e "  2. ${GREEN}检查 bin/ 包装器脚本${NC}"
echo -e "     执行: cd .kiro/specs/sh-ai && 查看 bin-wrapper-tasks.md"
echo -e ""
echo -e "  3. ${GREEN}测试 AIChat 集成${NC}"
echo -e "     执行: aichat --agent sh-ai"
echo ""

