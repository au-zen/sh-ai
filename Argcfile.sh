#!/usr/bin/env bash
set -e

# @meta dotenv

# SH-AI Agent Build Configuration
AGENT_NAME="sh-ai"
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$AGENT_DIR/src"
CORE_DIR="$SRC_DIR/core"
MODULES_DIR="$SRC_DIR/modules"
DIST_DIR="$AGENT_DIR/dist"
SCRIPTS_DIR="$AGENT_DIR/scripts"
OUTPUT_FILE="$DIST_DIR/tools.sh"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# @cmd Build the SH-AI agent (includes generating functions.json)
# @flag --skip-functions Skip functions.json generation
build() {
    echo -e "${BLUE}🚀 Building SH-AI Agent...${NC}"
    
    # Run the build script
    if [[ -f "$SCRIPTS_DIR/build.sh" ]]; then
        if [[ -n "${argc_skip_functions:-}" ]]; then
            SKIP_FUNCTIONS_JSON=1 bash "$SCRIPTS_DIR/build.sh"
        else
            bash "$SCRIPTS_DIR/build.sh"
        fi
    else
        _die "Build script not found: $SCRIPTS_DIR/build.sh"
    fi
    
    echo -e "${GREEN}✅ SH-AI Agent build completed${NC}"
}

# @cmd Generate function declarations (functions.json) for SH-AI agent using argc
# @flag --oneline Summary JSON in one line
# @flag --preview Preview without writing to file
generate-declarations() {
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        echo -e "${YELLOW}⚠️ Built tools.sh not found, building first...${NC}"
        build
    fi
    
    echo -e "${BLUE}📄 Generating function declarations using argc...${NC}"
    
    # Check if argc and jq are available
    if ! command -v argc &>/dev/null; then
        _die "argc not found. Please install argc: https://github.com/sigoden/argc"
    fi
    
    if ! command -v jq &>/dev/null; then
        _die "jq not found. Please install jq"
    fi
    
    local output_file="$AGENT_DIR/functions.json"
    
    # Generate declarations using argc
    if [[ -n "${argc_oneline:-}" ]]; then
        # Single line summary mode
        argc --argc-export "$OUTPUT_FILE" 2>/dev/null | \
        jq -r '.subcommands[]? | "\(.name): \(.describe)"' || {
            _die "Failed to generate declarations. Ensure functions have @cmd annotations."
        }
    else
        # Full JSON mode - OpenAI function calling format
        local json_output
        json_output=$(argc --argc-export "$OUTPUT_FILE" 2>/dev/null | \
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
        }) else [] end') || {
            _die "Failed to generate declarations. Ensure functions have @cmd annotations."
        }
        
        # Preview or write to file
        if [[ -n "${argc_preview:-}" ]]; then
            echo -e "${BLUE}📋 Preview of functions.json:${NC}"
            echo "$json_output" | jq '.'
        else
            # Backup existing file
            if [[ -f "$output_file" ]]; then
                cp "$output_file" "$output_file.bak"
                echo -e "${YELLOW}ℹ️ Backed up existing functions.json to functions.json.bak${NC}"
            fi
            
            # Write to file
            echo "$json_output" > "$output_file"
            echo -e "${GREEN}✅ Generated functions.json${NC}"
            
            # Show statistics
            local func_count
            func_count=$(echo "$json_output" | jq 'length')
            echo -e "${BLUE}📊 Generated $func_count function declarations${NC}"
            echo -e "${BLUE}📄 Output: $output_file${NC}"
            
            # Show function names
            echo -e "${BLUE}📋 Functions:${NC}"
            echo "$json_output" | jq -r '.[] | "  - \(.name): \(.description)"'
        fi
    fi
}

# @cmd Check SH-AI agent dependencies and environment
check() {
    echo -e "${BLUE}🔍 Checking SH-AI Agent...${NC}"
    
    local errors=0
    
    # Check required commands
    local required_commands=("bash" "ssh" "aichat" "jq")
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            echo -e "${GREEN}✓ $cmd found${NC}"
        else
            echo -e "${RED}✗ $cmd not found${NC}"
            ((errors++))
        fi
    done
    
    # Check directory structure
    local required_dirs=("$SRC_DIR" "$CORE_DIR" "$MODULES_DIR" "$DIST_DIR" "$SCRIPTS_DIR")
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo -e "${GREEN}✓ Directory exists: $(basename "$dir")${NC}"
        else
            echo -e "${RED}✗ Directory missing: $(basename "$dir")${NC}"
            ((errors++))
        fi
    done
    
    # Check core files
    local required_files=("$AGENT_DIR/index.yaml" "$SCRIPTS_DIR/build.sh")
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            echo -e "${GREEN}✓ File exists: $(basename "$file")${NC}"
        else
            echo -e "${RED}✗ File missing: $(basename "$file")${NC}"
            ((errors++))
        fi
    done
    
    # Check built output
    if [[ -f "$OUTPUT_FILE" ]]; then
        echo -e "${GREEN}✓ Built tools.sh exists${NC}"
        
        # Check syntax
        if bash -n "$OUTPUT_FILE"; then
            echo -e "${GREEN}✓ tools.sh syntax valid${NC}"
        else
            echo -e "${RED}✗ tools.sh syntax error${NC}"
            ((errors++))
        fi
    else
        echo -e "${YELLOW}⚠️ Built tools.sh not found (run 'build' first)${NC}"
    fi
    
    # Check environment variables
    local env_vars=("HOME" "USER")
    for var in "${env_vars[@]}"; do
        if [[ -n "${!var}" ]]; then
            echo -e "${GREEN}✓ Environment variable $var set${NC}"
        else
            echo -e "${YELLOW}⚠️ Environment variable $var not set${NC}"
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}✅ All checks passed${NC}"
        return 0
    else
        echo -e "${RED}❌ $errors errors found${NC}"
        return 1
    fi
}

# @cmd Test SH-AI agent functionality
test() {
    echo -e "${BLUE}🧪 Testing SH-AI Agent...${NC}"
    
    # Ensure agent is built
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        echo -e "${YELLOW}⚠️ Building agent first...${NC}"
        build
    fi
    
    # Test output module
    echo -e "${YELLOW}📝 Testing output module...${NC}"
    if bash "$OUTPUT_FILE" 2>/dev/null; then
        echo -e "${GREEN}✓ Output module test passed${NC}"
    else
        echo -e "${RED}✗ Output module test failed${NC}"
        return 1
    fi
    
    # Test function declarations
    echo -e "${YELLOW}📋 Testing function declarations...${NC}"
    if generate-declarations >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Function declarations generated successfully${NC}"
    else
        echo -e "${RED}✗ Function declarations generation failed${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ All tests passed${NC}"
}

# @cmd Clean build artifacts
clean() {
    echo -e "${BLUE}🧹 Cleaning SH-AI Agent...${NC}"
    
    # Remove built files
    if [[ -f "$OUTPUT_FILE" ]]; then
        rm -f "$OUTPUT_FILE"
        echo -e "${GREEN}✓ Removed $OUTPUT_FILE${NC}"
    fi
    
    # Remove generated declarations
    if [[ -f "$AGENT_DIR/functions.json" ]]; then
        rm -f "$AGENT_DIR/functions.json"
        echo -e "${GREEN}✓ Removed functions.json${NC}"
    fi
    
    echo -e "${GREEN}✅ Clean completed${NC}"
}

# @cmd Show SH-AI agent information
info() {
    echo -e "${BLUE}📊 SH-AI Agent Information${NC}"
    echo ""
    echo -e "${YELLOW}Agent Name:${NC} $AGENT_NAME"
    echo -e "${YELLOW}Agent Directory:${NC} $AGENT_DIR"
    echo -e "${YELLOW}Source Directory:${NC} $SRC_DIR"
    echo -e "${YELLOW}Build Output:${NC} $OUTPUT_FILE"
    echo ""
    
    if [[ -f "$AGENT_DIR/index.yaml" ]]; then
        echo -e "${YELLOW}Configuration:${NC}"
        echo -e "  Version: $(grep '^version:' "$AGENT_DIR/index.yaml" | cut -d' ' -f2)"
        echo -e "  Commands: $(grep -c '^  - name:' "$AGENT_DIR/index.yaml" 2>/dev/null || echo "0")"
    fi
    
    if [[ -f "$OUTPUT_FILE" ]]; then
        echo -e "${YELLOW}Build Status:${NC}"
        echo -e "  Built: $(date -r "$OUTPUT_FILE" '+%Y-%m-%d %H:%M:%S')"
        echo -e "  Size: $(du -h "$OUTPUT_FILE" | cut -f1)"
        echo -e "  Lines: $(wc -l < "$OUTPUT_FILE")"
    else
        echo -e "${YELLOW}Build Status:${NC} Not built"
    fi
    
    echo ""
}

# @cmd Run a specific SH-AI command for testing
# @arg command![connect|disconnect|list|status|detect|set_device_type|ai|exec|analy] The command to run
# @arg args* Additional arguments for the command
run() {
    local command="$1"
    shift
    
    echo -e "${BLUE}🚀 Running SH-AI command: $command${NC}"
    
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        echo -e "${YELLOW}⚠️ Building agent first...${NC}"
        build
    fi
    
    # Execute the command through the built tools.sh
    # This would typically be handled by the AIChat runtime
    echo -e "${YELLOW}Command:${NC} ssh_$command $*"
    echo -e "${YELLOW}Note:${NC} This would be executed by AIChat runtime"
}

# @cmd Validate agent configuration
validate() {
    echo -e "${BLUE}🔍 Validating SH-AI Agent Configuration...${NC}"
    
    local errors=0
    
    # Validate index.yaml
    if [[ -f "$AGENT_DIR/index.yaml" ]]; then
        echo -e "${GREEN}✓ index.yaml exists${NC}"
        
        # Check YAML syntax
        if python3 -c "import yaml; yaml.safe_load(open('$AGENT_DIR/index.yaml'))" 2>/dev/null; then
            echo -e "${GREEN}✓ index.yaml syntax valid${NC}"
        else
            echo -e "${RED}✗ index.yaml syntax error${NC}"
            ((errors++))
        fi
        
        # Check required fields for AIChat agent
        local required_fields=("name" "description" "version")
        for field in "${required_fields[@]}"; do
            if grep -q "^$field:" "$AGENT_DIR/index.yaml"; then
                echo -e "${GREEN}✓ Required field '$field' present${NC}"
            else
                echo -e "${RED}✗ Required field '$field' missing${NC}"
                ((errors++))
            fi
        done
        
        # Check optional but recommended fields
        local optional_fields=("instructions" "conversation_starters")
        for field in "${optional_fields[@]}"; do
            if grep -q "^$field:" "$AGENT_DIR/index.yaml"; then
                echo -e "${GREEN}✓ Optional field '$field' present${NC}"
            else
                echo -e "${YELLOW}⚠️ Optional field '$field' not present${NC}"
            fi
        done
    else
        echo -e "${RED}✗ index.yaml missing${NC}"
        ((errors++))
    fi
    
    # Validate source structure
    local core_modules=("output.sh" "ssh_core.sh")
    for module in "${core_modules[@]}"; do
        if [[ -f "$CORE_DIR/$module" ]]; then
            echo -e "${GREEN}✓ Core module $module exists${NC}"
        else
            echo -e "${YELLOW}⚠️ Core module $module missing (may be created in later tasks)${NC}"
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}✅ Configuration validation passed${NC}"
        return 0
    else
        echo -e "${RED}❌ $errors validation errors found${NC}"
        return 1
    fi
}

# Helper functions
_die() {
    echo -e "${RED}Error: $*${NC}" >&2
    exit 1
}

_info() {
    echo -e "${BLUE}Info: $*${NC}"
}

_warn() {
    echo -e "${YELLOW}Warning: $*${NC}"
}

_success() {
    echo -e "${GREEN}Success: $*${NC}"
}

# See more details at https://github.com/sigoden/argc
eval "$(argc --argc-eval "$0" "$@")"