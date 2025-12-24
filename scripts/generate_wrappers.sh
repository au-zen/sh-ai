#!/usr/bin/env bash
# AIChat Function Wrapper Generator
# Version: 1.0.0
# Description: Automatically generates executable wrapper scripts for AIChat agent functions
# 
# This script solves the AIChat function invocation issue where AIChat looks for
# executable files matching function names rather than calling functions in tools.sh
#
# Usage:
#   generate_wrappers.sh [options]
#
# Options:
#   --agent <name>      Agent name (default: sh-ai)
#   --force            Force overwrite existing wrappers
#   --clean            Clean obsolete wrappers
#   --dry-run          Show what would be done without executing
#   --verbose          Show detailed information
#   --help             Show this help message
#   --version          Show version information
#
# Examples:
#   # Generate wrappers for sh-ai agent
#   ./generate_wrappers.sh --agent sh-ai --verbose
#
#   # Force regenerate all wrappers
#   ./generate_wrappers.sh --agent sh-ai --force
#
#   # Clean obsolete wrappers
#   ./generate_wrappers.sh --agent sh-ai --clean
#
#   # Dry run to see what would be done
#   ./generate_wrappers.sh --agent sh-ai --dry-run --verbose

set -euo pipefail

# ============================================================================
# Constants and Configuration
# ============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
DEFAULT_AGENT="sh-ai"
AGENT_NAME="${DEFAULT_AGENT}"
FORCE_OVERWRITE=false
CLEAN_MODE=false
DRY_RUN=false
VERBOSE=false
VALIDATE_MODE=false
FILTER_PATTERN=""

# Path configuration
FUNCTIONS_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BIN_DIR="${FUNCTIONS_ROOT}/bin"

# Status icons
readonly ICON_SUCCESS="✅"
readonly ICON_ERROR="❌"
readonly ICON_WARNING="⚠️"
readonly ICON_INFO="ℹ️"
readonly ICON_GENERATE="🔧"
readonly ICON_CLEAN="🧹"
readonly ICON_CHECK="🔍"

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo "${ICON_INFO} $*"
}

log_success() {
    echo "${ICON_SUCCESS} $*"
}

log_warning() {
    echo "${ICON_WARNING} $*" >&2
}

log_error() {
    echo "${ICON_ERROR} $*" >&2
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "  → $*" >&2
    fi
}

log_dry_run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] $*"
    fi
}

# ============================================================================
# Error Handling Functions
# ============================================================================

handle_error() {
    local error_type="$1"
    local error_context="${2:-}"
    
    case "$error_type" in
        "missing_index")
            log_error "index.yaml not found"
            log_error "Expected location: $error_context"
            log_error "Please ensure you're in the correct agent directory"
            return 1
            ;;
        "invalid_yaml")
            log_error "Invalid YAML format in index.yaml"
            log_error "Details: $error_context"
            log_error "Please validate your YAML syntax"
            return 1
            ;;
        "missing_tools")
            log_error "tools.sh not found"
            log_error "Expected location: $error_context"
            log_error "Please ensure tools.sh exists in the agent directory"
            return 1
            ;;
        "permission_denied")
            log_error "Permission denied"
            log_error "Location: $error_context"
            log_error "Try: chmod +x $error_context"
            return 1
            ;;
        "bin_dir_creation_failed")
            log_error "Failed to create bin directory"
            log_error "Location: $error_context"
            log_error "Check permissions and disk space"
            return 1
            ;;
        "wrapper_generation_failed")
            log_error "Failed to generate wrapper"
            log_error "Function: $error_context"
            return 1
            ;;
        "no_functions_found")
            log_warning "No functions found in index.yaml"
            log_warning "Location: $error_context"
            log_warning "Please check your index.yaml configuration"
            return 1
            ;;
        *)
            log_error "Unknown error: $error_type"
            log_error "Context: $error_context"
            return 1
            ;;
    esac
}

# ============================================================================
# Usage and Version Functions
# ============================================================================

show_usage() {
    cat << EOF
AIChat Function Wrapper Generator v${SCRIPT_VERSION}

Usage:
  ${SCRIPT_NAME} [options]

Description:
  Automatically generates executable wrapper scripts for AIChat agent functions.
  This solves the AIChat function invocation issue where AIChat looks for
  executable files matching function names rather than calling functions in tools.sh.

Options:
  --agent <name>      Agent name (default: ${DEFAULT_AGENT})
  --filter <pattern>  Filter functions by regex pattern (e.g., 'ssh_exec.*')
  --force            Force overwrite existing wrappers
  --clean            Clean obsolete wrappers that no longer exist in index.yaml
  --validate         Validate existing wrappers without generating new ones
  --dry-run          Show what would be done without executing
  --verbose          Show detailed information during execution
  --help             Show this help message
  --version          Show version information

Examples:
  # Generate wrappers for sh-ai agent
  ${SCRIPT_NAME} --agent sh-ai --verbose

  # Force regenerate all wrappers
  ${SCRIPT_NAME} --agent sh-ai --force

  # Validate existing wrappers
  ${SCRIPT_NAME} --agent sh-ai --validate --verbose

  # Clean obsolete wrappers
  ${SCRIPT_NAME} --agent sh-ai --clean

  # Dry run to see what would be done
  ${SCRIPT_NAME} --agent sh-ai --dry-run --verbose

  # Generate wrappers for a different agent
  ${SCRIPT_NAME} --agent my-agent --verbose

Exit Codes:
  0  Success
  1  General error
  2  Invalid arguments
  3  Configuration error
  4  Generation error

For more information, see the documentation at:
  .kiro/specs/sh-ai/bin-wrapper-design.md

EOF
}

show_version() {
    cat << EOF
AIChat Function Wrapper Generator
Version: ${SCRIPT_VERSION}
Copyright (c) 2024

This tool is part of the SH-AI project and is designed to work with
the AIChat agent framework and llm-functions.

EOF
}

# ============================================================================
# Command Line Argument Parsing
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent)
                if [[ -z "${2:-}" ]]; then
                    log_error "Missing argument for --agent"
                    show_usage
                    exit 2
                fi
                AGENT_NAME="$2"
                shift 2
                ;;
            --filter)
                if [[ -z "${2:-}" ]]; then
                    log_error "Missing argument for --filter"
                    show_usage
                    exit 2
                fi
                FILTER_PATTERN="$2"
                shift 2
                ;;
            --force)
                FORCE_OVERWRITE=true
                shift
                ;;
            --clean)
                CLEAN_MODE=true
                shift
                ;;
            --validate)
                VALIDATE_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            --version|-v)
                show_version
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 2
                ;;
        esac
    done
}

# ============================================================================
# Function Extraction Functions
# ============================================================================

# Extract function names from index.yaml using grep/sed (no external dependencies)
extract_functions_grep() {
    local index_file="$1"
    
    if [[ ! -f "$index_file" ]]; then
        handle_error "missing_index" "$index_file"
        return 1
    fi
    
    log_verbose "Extracting functions using grep/sed method"
    
    # Extract function names from conversation_starters section
    # Pattern matches lines like: - "ssh_connect root@host"
    # Extracts just the function name (ssh_connect)
    local functions
    functions=$(grep -E '^\s*-\s*"[a-z_]+' "$index_file" | \
        sed -E 's/^\s*-\s*"([a-z_]+).*/\1/' | \
        grep -E '^ssh_' | \
        sort -u)
    
    if [[ -z "$functions" ]]; then
        log_verbose "No functions found in conversation_starters"
        return 1
    fi
    
    echo "$functions"
    return 0
}

# Extract function names from index.yaml using yq (optional, requires yq tool)
extract_functions_yq() {
    local index_file="$1"
    
    if [[ ! -f "$index_file" ]]; then
        handle_error "missing_index" "$index_file"
        return 1
    fi
    
    # Check if yq is available
    if ! command -v yq &> /dev/null; then
        log_verbose "yq not found, falling back to grep method"
        extract_functions_grep "$index_file"
        return $?
    fi
    
    log_verbose "Extracting functions using yq method"
    
    # Use yq to parse YAML and extract function names
    local functions
    functions=$(yq eval '.conversation_starters[]' "$index_file" 2>/dev/null | \
        grep -oE '^[a-z_]+' | \
        grep -E '^ssh_' | \
        sort -u)
    
    if [[ -z "$functions" ]]; then
        log_verbose "No functions found, trying grep method"
        extract_functions_grep "$index_file"
        return $?
    fi
    
    echo "$functions"
    return 0
}

# Validate a function name
validate_function_name() {
    local func_name="$1"
    
    # Function name must:
    # - Start with a letter or underscore
    # - Contain only letters, numbers, and underscores
    # - Not be empty
    if [[ -z "$func_name" ]]; then
        return 1
    fi
    
    if [[ ! "$func_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        log_verbose "Invalid function name: $func_name"
        return 1
    fi
    
    return 0
}

# Extract and validate function list from index.yaml
extract_function_list() {
    local index_file="$1"
    
    log_verbose "Extracting function list from: $index_file"
    
    # Try yq first, fall back to grep
    local functions
    if command -v yq &> /dev/null; then
        functions=$(extract_functions_yq "$index_file")
    else
        functions=$(extract_functions_grep "$index_file")
    fi
    
    if [[ -z "$functions" ]]; then
        handle_error "no_functions_found" "$index_file"
        return 1
    fi
    
    # Validate and deduplicate function names
    local validated_functions=()
    local seen_functions=()
    
    while IFS= read -r func; do
        # Skip empty lines
        [[ -z "$func" ]] && continue
        
        # Validate function name
        if ! validate_function_name "$func"; then
            log_warning "Skipping invalid function name: $func"
            continue
        fi
        
        # Check for duplicates
        if [[ " ${seen_functions[*]} " =~ " ${func} " ]]; then
            log_verbose "Skipping duplicate function: $func"
            continue
        fi
        
        validated_functions+=("$func")
        seen_functions+=("$func")
        log_verbose "Found function: $func"
    done <<< "$functions"
    
    if [[ ${#validated_functions[@]} -eq 0 ]]; then
        handle_error "no_functions_found" "$index_file"
        return 1
    fi
    
    # Output validated functions
    printf '%s\n' "${validated_functions[@]}"
    return 0
}

# ============================================================================
# Function Filtering and Sorting
# ============================================================================

# Sort function names alphabetically
sort_functions() {
    local functions=("$@")
    
    if [[ ${#functions[@]} -eq 0 ]]; then
        return 0
    fi
    
    printf '%s\n' "${functions[@]}" | sort -u
}

# Filter functions by pattern
filter_functions() {
    local pattern="$1"
    shift
    local functions=("$@")
    
    if [[ -z "$pattern" ]]; then
        printf '%s\n' "${functions[@]}"
        return 0
    fi
    
    log_verbose "Filtering functions with pattern: $pattern"
    
    local filtered=()
    for func in "${functions[@]}"; do
        if [[ "$func" =~ $pattern ]]; then
            filtered+=("$func")
            log_verbose "Matched: $func"
        fi
    done
    
    if [[ ${#filtered[@]} -eq 0 ]]; then
        log_warning "No functions matched pattern: $pattern"
        return 1
    fi
    
    printf '%s\n' "${filtered[@]}"
    return 0
}

# Remove invalid or duplicate function names
deduplicate_functions() {
    local functions=("$@")
    
    if [[ ${#functions[@]} -eq 0 ]]; then
        return 0
    fi
    
    # Use associative array for deduplication
    declare -A seen
    local unique=()
    
    for func in "${functions[@]}"; do
        # Skip if already seen
        if [[ -n "${seen[$func]:-}" ]]; then
            log_verbose "Removing duplicate: $func"
            continue
        fi
        
        # Skip if invalid
        if ! validate_function_name "$func"; then
            log_verbose "Removing invalid: $func"
            continue
        fi
        
        seen[$func]=1
        unique+=("$func")
    done
    
    printf '%s\n' "${unique[@]}"
    return 0
}

# Process function list: extract, validate, filter, sort
process_function_list() {
    local index_file="$1"
    local filter_pattern="${2:-}"
    
    log_verbose "Processing function list..."
    
    # Extract functions
    local functions
    if ! functions=$(extract_function_list "$index_file"); then
        return 1
    fi
    
    # Convert to array
    local func_array=()
    while IFS= read -r func; do
        [[ -n "$func" ]] && func_array+=("$func")
    done <<< "$functions"
    
    log_verbose "Extracted ${#func_array[@]} functions"
    
    # Apply filter if provided
    if [[ -n "$filter_pattern" ]]; then
        local filtered
        if ! filtered=$(filter_functions "$filter_pattern" "${func_array[@]}"); then
            return 1
        fi
        
        func_array=()
        while IFS= read -r func; do
            [[ -n "$func" ]] && func_array+=("$func")
        done <<< "$filtered"
        
        log_verbose "Filtered to ${#func_array[@]} functions"
    fi
    
    # Deduplicate
    local deduplicated
    deduplicated=$(deduplicate_functions "${func_array[@]}")
    
    func_array=()
    while IFS= read -r func; do
        [[ -n "$func" ]] && func_array+=("$func")
    done <<< "$deduplicated"
    
    log_verbose "Deduplicated to ${#func_array[@]} functions"
    
    # Sort
    local sorted
    sorted=$(sort_functions "${func_array[@]}")
    
    echo "$sorted"
    return 0
}

# ============================================================================
# Path Resolution and Validation Functions
# ============================================================================

# Resolve the relative path from bin/ directory to agent's tools.sh
resolve_tools_path() {
    local bin_dir="$1"
    local agent_name="$2"
    local use_absolute="${3:-false}"
    
    log_verbose "Resolving tools.sh path for agent: $agent_name"
    
    if [[ "$use_absolute" == "true" ]]; then
        # Return absolute path
        local agent_dir="${FUNCTIONS_ROOT}/agents/${agent_name}"
        local tools_path="${agent_dir}/tools.sh"
        
        # Resolve symlinks and normalize path
        if [[ -e "$tools_path" ]]; then
            tools_path=$(readlink -f "$tools_path" 2>/dev/null || realpath "$tools_path" 2>/dev/null || echo "$tools_path")
        fi
        
        log_verbose "Resolved absolute path: $tools_path"
        echo "$tools_path"
    else
        # Return relative path from bin/ to agents/<agent>/tools.sh
        local relative_path="../agents/${agent_name}/tools.sh"
        log_verbose "Resolved relative path: $relative_path"
        echo "$relative_path"
    fi
    
    return 0
}

# Validate that tools.sh exists and is accessible
validate_tools_path() {
    local tools_path="$1"
    local context="${2:-}"
    
    log_verbose "Validating tools.sh path: $tools_path"
    
    # Check if file exists
    if [[ ! -f "$tools_path" ]]; then
        handle_error "missing_tools" "$tools_path"
        return 1
    fi
    
    log_verbose "✓ File exists"
    
    # Check if file is readable
    if [[ ! -r "$tools_path" ]]; then
        log_error "tools.sh is not readable: $tools_path"
        log_error "Please check file permissions"
        return 1
    fi
    
    log_verbose "✓ File is readable"
    
    # Check if file contains valid bash syntax
    if ! bash -n "$tools_path" 2>/dev/null; then
        log_error "tools.sh contains syntax errors: $tools_path"
        log_error "Please validate your bash syntax"
        
        # Show syntax errors in verbose mode
        if [[ "$VERBOSE" == "true" ]]; then
            log_error "Syntax check output:"
            bash -n "$tools_path" 2>&1 | head -10 >&2
        fi
        
        return 1
    fi
    
    log_verbose "✓ Bash syntax is valid"
    
    # Additional validation: check if it's actually a bash script
    if ! head -1 "$tools_path" | grep -qE '^#!/.*(bash|sh)'; then
        log_warning "tools.sh may not be a bash script (missing or invalid shebang)"
        log_warning "First line: $(head -1 "$tools_path")"
    fi
    
    log_verbose "✓ tools.sh validation passed"
    return 0
}

# Resolve and validate tools.sh path for an agent
resolve_and_validate_tools_path() {
    local agent_name="$1"
    local use_absolute="${2:-false}"
    
    log_verbose "Resolving and validating tools.sh for agent: $agent_name"
    
    # Resolve path
    local tools_path
    if [[ "$use_absolute" == "true" ]]; then
        tools_path=$(resolve_tools_path "$BIN_DIR" "$agent_name" "true")
    else
        # For validation, we need the actual path, not relative
        local agent_dir="${FUNCTIONS_ROOT}/agents/${agent_name}"
        tools_path="${agent_dir}/tools.sh"
    fi
    
    # Validate path
    if ! validate_tools_path "$tools_path" "$agent_name"; then
        return 1
    fi
    
    log_verbose "✓ Path resolution and validation successful"
    return 0
}

# Calculate relative path from one directory to another
calculate_relative_path() {
    local from_dir="$1"
    local to_file="$2"
    
    # Get absolute paths
    local from_abs=$(cd "$from_dir" && pwd)
    local to_abs=$(cd "$(dirname "$to_file")" && pwd)/$(basename "$to_file")
    
    # Calculate relative path
    local common_part="$from_abs"
    local result=""
    
    while [[ "${to_abs#$common_part}" == "${to_abs}" ]]; do
        common_part=$(dirname "$common_part")
        if [[ -z "$result" ]]; then
            result=".."
        else
            result="../$result"
        fi
    done
    
    if [[ "$common_part" == "/" ]]; then
        result="$result/"
    fi
    
    local forward_part="${to_abs#$common_part}"
    forward_part="${forward_part#/}"
    
    if [[ -n "$forward_part" ]]; then
        if [[ -n "$result" ]]; then
            result="$result/$forward_part"
        else
            result="$forward_part"
        fi
    fi
    
    echo "$result"
}

# Handle symlinks in path resolution
resolve_symlinks() {
    local path="$1"
    
    # Try readlink -f first (GNU coreutils)
    if command -v readlink &>/dev/null && readlink -f "$path" &>/dev/null; then
        readlink -f "$path"
        return 0
    fi
    
    # Try realpath (alternative)
    if command -v realpath &>/dev/null; then
        realpath "$path" 2>/dev/null
        return 0
    fi
    
    # Fallback: manual resolution
    if [[ -L "$path" ]]; then
        local link_target=$(readlink "$path")
        if [[ "$link_target" == /* ]]; then
            echo "$link_target"
        else
            echo "$(dirname "$path")/$link_target"
        fi
    else
        echo "$path"
    fi
    
    return 0
}

# ============================================================================
# Wrapper Template and Generation Functions
# ============================================================================

# Generate wrapper script template
generate_wrapper_template() {
    local function_name="$1"
    local agent_name="$2"
    local tools_relative_path="$3"
    local timestamp="$4"
    
    cat << EOF
#!/usr/bin/env bash
# Auto-generated wrapper for ${agent_name} agent function: ${function_name}
# Generated: ${timestamp}
# Generator version: ${SCRIPT_VERSION}
# DO NOT EDIT THIS FILE MANUALLY - Regenerate using generate_wrappers.sh

set -euo pipefail

# ============================================================================
# Wrapper Configuration
# ============================================================================

readonly WRAPPER_FUNCTION="${function_name}"
readonly WRAPPER_AGENT="${agent_name}"
readonly WRAPPER_VERSION="${SCRIPT_VERSION}"
readonly WRAPPER_GENERATED="${timestamp}"

# ============================================================================
# Path Resolution
# ============================================================================

# Locate the tools.sh script
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
TOOLS_SCRIPT="\${SCRIPT_DIR}/${tools_relative_path}"

# ============================================================================
# Error Handling
# ============================================================================

# Verify tools.sh exists
if [[ ! -f "\$TOOLS_SCRIPT" ]]; then
    echo "Error: tools.sh not found at \$TOOLS_SCRIPT" >&2
    echo "Expected path: \${SCRIPT_DIR}/${tools_relative_path}" >&2
    echo "Wrapper: \${WRAPPER_FUNCTION} (agent: \${WRAPPER_AGENT})" >&2
    exit 1
fi

# Verify tools.sh is readable
if [[ ! -r "\$TOOLS_SCRIPT" ]]; then
    echo "Error: tools.sh is not readable at \$TOOLS_SCRIPT" >&2
    echo "Please check file permissions" >&2
    exit 1
fi

# ============================================================================
# Debug Mode Support
# ============================================================================

# Enable debug mode if requested
if [[ "\${SH_AI_DEBUG:-false}" == "true" ]] || [[ "\${DEBUG:-false}" == "true" ]]; then
    echo "[DEBUG] Wrapper: \${WRAPPER_FUNCTION}" >&2
    echo "[DEBUG] Agent: \${WRAPPER_AGENT}" >&2
    echo "[DEBUG] Tools script: \$TOOLS_SCRIPT" >&2
    echo "[DEBUG] Arguments: \$*" >&2
    echo "[DEBUG] Argument count: \$#" >&2
fi

# ============================================================================
# Function Execution
# ============================================================================

# Source the tools.sh script
source "\$TOOLS_SCRIPT"

# Call the actual function with all arguments
${function_name} "\$@"
EOF
}

# Generate a single wrapper script
generate_wrapper() {
    local function_name="$1"
    local bin_dir="$2"
    local agent_name="$3"
    local tools_relative_path="$4"
    
    local wrapper_path="${bin_dir}/${function_name}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_verbose "Generating wrapper: $function_name"
    
    # Check if wrapper already exists
    if [[ -f "$wrapper_path" ]] && [[ "$FORCE_OVERWRITE" != "true" ]]; then
        log_verbose "Wrapper already exists (use --force to overwrite): $function_name"
        return 0
    fi
    
    # Generate wrapper content
    local wrapper_content
    wrapper_content=$(generate_wrapper_template "$function_name" "$agent_name" "$tools_relative_path" "$timestamp")
    
    # Write wrapper to file
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Would create wrapper: $wrapper_path"
        return 0
    fi
    
    if echo "$wrapper_content" > "$wrapper_path"; then
        # Set executable permission
        if chmod +x "$wrapper_path"; then
            log_verbose "Wrapper created successfully: $function_name"
            return 0
        else
            log_error "Failed to set executable permission: $wrapper_path"
            return 1
        fi
    else
        log_error "Failed to write wrapper: $wrapper_path"
        return 1
    fi
}

# Generate all wrappers for a list of functions
generate_all_wrappers() {
    local bin_dir="$1"
    local agent_name="$2"
    local tools_relative_path="$3"
    shift 3
    local functions=("$@")
    
    local total=${#functions[@]}
    local generated=0
    local skipped=0
    local failed=0
    
    log_info "Generating wrappers for $total functions..."
    
    for func in "${functions[@]}"; do
        if generate_wrapper "$func" "$bin_dir" "$agent_name" "$tools_relative_path"; then
            if [[ "$DRY_RUN" != "true" ]]; then
                if [[ -f "${bin_dir}/${func}" ]]; then
                    ((generated++))
                else
                    ((skipped++))
                fi
            else
                ((generated++))
            fi
        else
            ((failed++))
            log_warning "Failed to generate wrapper: $func"
        fi
        
        # Show progress in verbose mode
        if [[ "$VERBOSE" == "true" ]]; then
            local current=$((generated + skipped + failed))
            local percentage=$((current * 100 / total))
            log_verbose "Progress: ${current}/${total} (${percentage}%)"
        fi
    done
    
    # Summary
    echo ""
    log_success "Wrapper generation completed"
    log_info "Generated: $generated"
    
    if [[ $skipped -gt 0 ]]; then
        log_info "Skipped: $skipped (already exist, use --force to overwrite)"
    fi
    
    if [[ $failed -gt 0 ]]; then
        log_warning "Failed: $failed"
        return 1
    fi
    
    return 0
}

# ============================================================================
# Wrapper Validation Functions
# ============================================================================

# Validate a single wrapper script
validate_wrapper() {
    local wrapper_path="$1"
    local function_name="$2"
    local verbose="${3:-false}"
    
    local errors=0
    
    if [[ "$verbose" == "true" ]]; then
        log_verbose "Validating wrapper: $function_name"
    fi
    
    # Test 1: File existence
    if [[ ! -f "$wrapper_path" ]]; then
        log_error "Wrapper not found: $wrapper_path"
        return 1
    fi
    
    if [[ "$verbose" == "true" ]]; then
        log_verbose "✓ File exists"
    fi
    
    # Test 2: Executable permission
    if [[ ! -x "$wrapper_path" ]]; then
        log_error "Wrapper not executable: $wrapper_path"
        log_error "Try: chmod +x $wrapper_path"
        ((errors++))
    else
        if [[ "$verbose" == "true" ]]; then
            log_verbose "✓ Executable permission set"
        fi
    fi
    
    # Test 3: Bash syntax validation
    if ! bash -n "$wrapper_path" 2>/dev/null; then
        log_error "Syntax error in wrapper: $wrapper_path"
        
        # Show syntax errors in verbose mode
        if [[ "$verbose" == "true" ]]; then
            log_error "Syntax check output:"
            bash -n "$wrapper_path" 2>&1 | head -5 >&2
        fi
        
        ((errors++))
    else
        if [[ "$verbose" == "true" ]]; then
            log_verbose "✓ Bash syntax valid"
        fi
    fi
    
    # Test 4: Verify wrapper contains necessary components
    local has_shebang=false
    local has_tools_path=false
    local has_source=false
    local has_function_call=false
    
    # Check for shebang
    if head -1 "$wrapper_path" | grep -qE '^#!/.*(bash|sh)'; then
        has_shebang=true
        if [[ "$verbose" == "true" ]]; then
            log_verbose "✓ Shebang present"
        fi
    else
        log_error "Missing or invalid shebang in: $wrapper_path"
        ((errors++))
    fi
    
    # Check for TOOLS_SCRIPT variable
    if grep -q "TOOLS_SCRIPT=" "$wrapper_path"; then
        has_tools_path=true
        if [[ "$verbose" == "true" ]]; then
            log_verbose "✓ TOOLS_SCRIPT path defined"
        fi
    else
        log_error "Missing TOOLS_SCRIPT path in: $wrapper_path"
        ((errors++))
    fi
    
    # Check for source command
    if grep -q "source.*TOOLS_SCRIPT" "$wrapper_path"; then
        has_source=true
        if [[ "$verbose" == "true" ]]; then
            log_verbose "✓ Source command present"
        fi
    else
        log_error "Missing source command in: $wrapper_path"
        ((errors++))
    fi
    
    # Check for function call
    if grep -q "^${function_name} " "$wrapper_path" || grep -q "^${function_name}\$" "$wrapper_path"; then
        has_function_call=true
        if [[ "$verbose" == "true" ]]; then
            log_verbose "✓ Function call present"
        fi
    else
        log_warning "Function call not found in: $wrapper_path"
        log_warning "Expected: ${function_name} \"\$@\""
        # This is a warning, not an error, as the function might be called differently
    fi
    
    # Test 5: Verify tools.sh path is resolvable
    local tools_path_line
    tools_path_line=$(grep "TOOLS_SCRIPT=" "$wrapper_path" | head -1)
    
    if [[ -n "$tools_path_line" ]]; then
        # Extract the path (this is a simplified check)
        if [[ "$verbose" == "true" ]]; then
            log_verbose "Tools path line: $tools_path_line"
        fi
        
        # Check if it contains a relative path pattern
        if echo "$tools_path_line" | grep -q '\.\./agents/'; then
            if [[ "$verbose" == "true" ]]; then
                log_verbose "✓ Relative path pattern found"
            fi
        else
            log_warning "Unusual tools.sh path pattern in: $wrapper_path"
        fi
    fi
    
    # Return result
    if [[ $errors -eq 0 ]]; then
        if [[ "$verbose" == "true" ]]; then
            log_success "Wrapper validation passed: $function_name"
        fi
        return 0
    else
        log_error "Wrapper validation failed: $function_name ($errors errors)"
        return 1
    fi
}

# Validate all wrappers for a list of functions
validate_all_wrappers() {
    local bin_dir="$1"
    shift
    local functions=("$@")
    
    local total=${#functions[@]}
    local passed=0
    local failed=0
    local missing=0
    
    log_info "Validating $total wrappers..."
    echo ""
    
    for func in "${functions[@]}"; do
        local wrapper_path="${bin_dir}/${func}"
        
        # Check if wrapper exists
        if [[ ! -f "$wrapper_path" ]]; then
            log_warning "Wrapper missing: $func"
            ((missing++))
            continue
        fi
        
        # Validate wrapper
        if validate_wrapper "$wrapper_path" "$func" "$VERBOSE"; then
            ((passed++))
            if [[ "$VERBOSE" != "true" ]]; then
                echo "  ${ICON_SUCCESS} $func"
            fi
        else
            ((failed++))
            if [[ "$VERBOSE" != "true" ]]; then
                echo "  ${ICON_ERROR} $func"
            fi
        fi
    done
    
    # Generate validation report
    echo ""
    echo "========================================"
    echo "Validation Report"
    echo "========================================"
    echo ""
    log_info "Total wrappers: $total"
    
    if [[ $passed -gt 0 ]]; then
        log_success "Passed: $passed"
    fi
    
    if [[ $missing -gt 0 ]]; then
        log_warning "Missing: $missing"
    fi
    
    if [[ $failed -gt 0 ]]; then
        log_error "Failed: $failed"
    fi
    
    echo ""
    
    # Calculate success rate
    local validated=$((passed + failed))
    if [[ $validated -gt 0 ]]; then
        local success_rate=$((passed * 100 / validated))
        log_info "Success rate: ${success_rate}%"
    fi
    
    echo ""
    
    # Return status
    if [[ $failed -gt 0 ]]; then
        log_error "Some wrappers failed validation"
        return 1
    elif [[ $missing -gt 0 ]]; then
        log_warning "Some wrappers are missing"
        return 1
    else
        log_success "All wrappers passed validation"
        return 0
    fi
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Display header
    if [[ "$VERBOSE" == "true" ]]; then
        echo "========================================"
        echo "AIChat Function Wrapper Generator"
        echo "Version: ${SCRIPT_VERSION}"
        echo "========================================"
        echo ""
        log_verbose "Agent: ${AGENT_NAME}"
        log_verbose "Functions root: ${FUNCTIONS_ROOT}"
        log_verbose "Bin directory: ${BIN_DIR}"
        log_verbose "Force overwrite: ${FORCE_OVERWRITE}"
        log_verbose "Clean mode: ${CLEAN_MODE}"
        log_verbose "Validate mode: ${VALIDATE_MODE}"
        log_verbose "Dry run: ${DRY_RUN}"
        echo ""
    fi
    
    # Validate configuration
    log_info "Validating configuration..."
    
    # Check agent directory exists
    local agent_dir="${FUNCTIONS_ROOT}/agents/${AGENT_NAME}"
    if [[ ! -d "$agent_dir" ]]; then
        handle_error "missing_index" "$agent_dir"
        exit 3
    fi
    log_verbose "Agent directory found: $agent_dir"
    
    # Check index.yaml exists
    local index_file="${agent_dir}/index.yaml"
    if [[ ! -f "$index_file" ]]; then
        handle_error "missing_index" "$index_file"
        exit 3
    fi
    log_verbose "index.yaml found: $index_file"
    
    # Check and validate tools.sh
    log_info "Validating tools.sh..."
    if ! resolve_and_validate_tools_path "$AGENT_NAME"; then
        log_error "tools.sh validation failed"
        exit 3
    fi
    
    log_success "Configuration validated"
    echo ""
    
    # Ensure bin directory exists
    if [[ ! -d "$BIN_DIR" ]]; then
        log_info "Creating bin directory: $BIN_DIR"
        if [[ "$DRY_RUN" == "false" ]]; then
            if ! mkdir -p "$BIN_DIR"; then
                handle_error "bin_dir_creation_failed" "$BIN_DIR"
                exit 3
            fi
        else
            log_dry_run "Would create directory: $BIN_DIR"
        fi
    fi
    
    # Success message
    log_success "Configuration validated"
    echo ""
    
    # Extract and process function list
    log_info "Extracting function list from index.yaml..."
    
    if [[ -n "$FILTER_PATTERN" ]]; then
        log_verbose "Applying filter pattern: $FILTER_PATTERN"
    fi
    
    local function_list
    if ! function_list=$(process_function_list "$index_file" "$FILTER_PATTERN"); then
        log_error "Failed to extract function list"
        exit 4
    fi
    
    # Convert to array for processing
    local functions=()
    while IFS= read -r func; do
        [[ -n "$func" ]] && functions+=("$func")
    done <<< "$function_list"
    
    if [[ ${#functions[@]} -eq 0 ]]; then
        log_error "No valid functions found in index.yaml"
        exit 4
    fi
    
    log_success "Found ${#functions[@]} functions"
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        log_info "Function list:"
        for func in "${functions[@]}"; do
            echo "  - $func" >&2
        done
    fi
    
    echo ""
    
    # Validation mode - validate existing wrappers
    if [[ "$VALIDATE_MODE" == "true" ]]; then
        log_info "Validation mode - checking existing wrappers"
        echo ""
        
        if validate_all_wrappers "$BIN_DIR" "${functions[@]}"; then
            echo ""
            log_success "Validation completed successfully"
            exit 0
        else
            echo ""
            log_error "Validation completed with errors"
            exit 4
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - no changes will be made"
        echo ""
        log_info "Would generate wrappers for ${#functions[@]} functions:"
        for func in "${functions[@]}"; do
            echo "  ${ICON_GENERATE} $func -> ${BIN_DIR}/$func"
        done
        echo ""
        log_success "Dry run completed"
        exit 0
    fi
    
    # Calculate relative path from bin/ to agent tools.sh using path resolver
    log_verbose "Calculating tools.sh relative path..."
    local tools_relative_path
    tools_relative_path=$(resolve_tools_path "$BIN_DIR" "$AGENT_NAME" "false")
    log_verbose "Using relative path: $tools_relative_path"
    
    # Generate all wrappers
    echo ""
    if generate_all_wrappers "$BIN_DIR" "$AGENT_NAME" "$tools_relative_path" "${functions[@]}"; then
        echo ""
        log_success "All wrappers generated successfully"
        log_info "Wrappers location: $BIN_DIR"
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo ""
            log_info "Generated wrappers:"
            for func in "${functions[@]}"; do
                if [[ -f "${BIN_DIR}/${func}" ]]; then
                    echo "  ${ICON_SUCCESS} $func"
                fi
            done
        fi
        
        exit 0
    else
        echo ""
        log_error "Some wrappers failed to generate"
        exit 4
    fi
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
