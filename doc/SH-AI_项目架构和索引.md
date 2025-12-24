# SH-AI 项目架构和索引文档

## 项目概述

SH-AI 是一个 AI 增强型 SSH 管理工具，采用模块化架构设计，支持智能设备检测、自然语言命令处理和安全执行。项目遵循 llm-functions 标准，与 AIChat 深度集成。

### 核心特性
- 🤖 AI 增强的 SSH 连接管理
- 🔍 自动设备类型检测和缓存
- 📝 统一的 Markdown 格式输出
- 🔄 双模式支持 (AIChat/CLI)
- 🛡️ 安全的命令执行机制
- 📊 结构化 JSON 响应

## 项目架构

### 1. 目录结构

```
functions/agents/sh-ai/
├── src/                          # 源代码模块
│   ├── core/                     # 核心功能模块
│   │   ├── output.sh            # 输出格式化核心
│   │   ├── cache.sh             # 缓存管理系统
│   │   ├── ssh_core.sh          # SSH 核心功能
│   │   ├── device_detect.sh     # 设备检测引擎
│   │   └── ai_command.sh        # AI 命令处理
│   └── modules/                  # 业务功能模块
│       ├── ssh_connect.sh       # 连接管理
│       ├── ssh_exec.sh          # 命令执行
│       ├── ssh_ai.sh            # AI 智能分析
│       ├── ssh_status.sh        # 状态查询
│       ├── ssh_list.sh          # 连接列表
│       ├── ssh_detect.sh        # 设备检测
│       ├── ssh_analy.sh         # 结果分析
│       ├── ssh_cleanup.sh       # 连接清理
│       ├── ssh_disconnect.sh    # 断开连接
│       ├── ssh_reconnect.sh     # 重新连接
│       └── ssh_exec_raw.sh      # 原始执行
├── scripts/                      # 构建和工具脚本
│   └── build.sh                 # 自动构建脚本
├── dist/                        # 构建输出目录
│   └── tools.sh                 # 合并后的单文件
├── index.yaml                   # Agent 配置文件
├── functions.json               # OpenAI 函数声明
├── tools.txt                    # 工具列表
└── tools.sh -> dist/tools.sh    # 符号链接
```

### 2. 核心架构设计

#### 2.1 模块化架构

**核心模块 (src/core/)**
- **output.sh**: 统一输出格式化，支持 AIChat/CLI 双模式
- **cache.sh**: 设备信息缓存，24小时有效期
- **ssh_core.sh**: SSH ControlMaster 连接管理
- **device_detect.sh**: 智能设备类型检测
- **ai_command.sh**: AI 命令生成和处理

**业务模块 (src/modules/)**
- **连接管理**: ssh_connect, ssh_disconnect, ssh_reconnect
- **命令执行**: ssh_exec, ssh_exec_raw
- **智能分析**: ssh_ai, ssh_analy, ssh_detect
- **状态管理**: ssh_status, ssh_list, ssh_cleanup

#### 2.2 构建系统

**自动化构建流程**:
1. 按依赖顺序合并核心模块
2. 自动发现并合并业务模块
3. 添加 argc 评估入口点
4. 生成 llm-functions 标准文件
5. 语法检查和 argc 兼容性验证

**构建输出**:
- `dist/tools.sh`: 单文件可执行工具
- `functions.json`: OpenAI 函数调用声明
- `tools.txt`: 工具列表文档

#### 2.3 包装器系统

**二进制包装器 (functions/bin/)**
- 每个函数对应一个独立的可执行文件
- 自动路径解析和错误处理
- 调试模式支持
- 统一的错误报告机制

## 功能模块索引

### 3. 核心功能模块详解

#### 3.1 输出格式化系统 (output.sh)

**主要功能**:
- 双模式输出支持 (AIChat JSON / CLI 直接输出)
- 输出缓冲和批量处理
- Markdown 格式化
- 状态级别管理 (info/success/warning/error)
- JSON 响应构建和验证

**关键函数**:
```bash
_output()           # 基础输出函数
_success()          # 成功信息输出
_error()            # 错误信息输出
_warning()          # 警告信息输出
_output_header()    # 标题输出
_output_code()      # 代码块输出
_build_json_response() # JSON 响应构建
```

**输出模式检测**:
- 检查 `$LLM_OUTPUT` 环境变量
- 自动切换 AIChat/CLI 模式
- 原始输出模式支持

#### 3.2 缓存管理系统 (cache.sh)

**缓存策略**:
- 设备类型缓存 (24小时有效期)
- 连接状态缓存
- 命令结果缓存 (可选)

**缓存位置**:
- `~/.config/aichat/functions/cache/sh-ai/`
- 环境变量可配置路径

#### 3.3 SSH 核心功能 (ssh_core.sh)

**ControlMaster 管理**:
- 自动建立持久连接
- 连接复用和状态检测
- 超时和重连机制
- 安全的连接清理

**目标解析**:
- 支持 `user@host[:port]` 格式
- 默认端口 22
- 参数验证和标准化

#### 3.4 设备检测引擎 (device_detect.sh)

**检测方法**:
1. SSH Banner 分析
2. 系统信息命令执行
3. 特征文件检测
4. AI 辅助分析

**支持的设备类型**:
- Linux (各发行版)
- OpenWrt / LEDE
- Cisco IOS
- Huawei VRP
- MikroTik RouterOS
- 通用 Unix 系统

### 4. 业务功能模块详解

#### 4.1 连接管理模块

**ssh_connect**:
```bash
# @cmd 建立 SSH ControlMaster 连接
# @option --target! <user@host[:port]> SSH 目标
ssh_connect() {
    # 参数解析 (argc/JSON/直接参数)
    # 连接建立
    # 设备类型自动检测
    # 状态缓存更新
}
```

**ssh_status**:
```bash
# @cmd 查看 SSH 连接状态
# @arg target <user@host[:port]> 可选的特定目标
ssh_status() {
    # 连接状态检查
    # 设备信息显示
    # 缓存状态报告
}
```

#### 4.2 命令执行模块

**ssh_exec**:
```bash
# @cmd 在远程主机执行命令
# @option --target <user@host[:port]> SSH 目标
# @arg command! 要执行的命令
ssh_exec() {
    # 目标推断 (使用最后连接的目标)
    # 安全命令验证
    # 执行结果格式化
}
```

**ssh_ai**:
```bash
# @cmd AI 增强的智能命令执行
# @arg intent! 自然语言意图描述
# @option --target <user@host[:port]> SSH 目标
ssh_ai() {
    # 意图理解和命令生成
    # 设备类型适配
    # 安全性检查
    # 结果智能分析
}
```

#### 4.3 智能分析模块

**ssh_analy**:
```bash
# @cmd 分析命令执行结果
# @arg result! 要分析的结果内容
# @option --target <user@host[:port]> SSH 目标
ssh_analy() {
    # 结果解析和结构化
    # 异常检测
    # 建议生成
}
```

**ssh_detect**:
```bash
# @cmd 检测远程设备类型
# @option --target! <user@host[:port]> SSH 目标
ssh_detect() {
    # 多方法设备检测
    # 结果缓存
    # 置信度评估
}
```

## 配置和集成

### 5. Agent 配置 (index.yaml)

**核心配置项**:
```yaml
name: sh-ai
description: AI-enhanced SSH management tool
version: 1.1.0
instructions: |
  # 函数选择规则
  # 连接状态跟踪
  # 响应格式规范
  # 安全策略
```

**优化特性**:
- 精简指令减少 token 消耗
- 禁用 RAG 提升响应速度
- 严格的函数调用规则
- 防止模型幻觉机制

### 6. 函数声明 (functions.json)

**自动生成流程**:
1. argc 注释解析
2. 参数类型推断
3. OpenAI 格式转换
4. JSON 验证和优化

**声明格式**:
```json
{
  "name": "ssh_connect",
  "description": "建立 SSH ControlMaster 连接",
  "parameters": {
    "type": "object",
    "properties": {
      "target": {
        "type": "string",
        "description": "SSH 目标 (user@host[:port])"
      }
    },
    "required": ["target"]
  }
}
```

### 7. 包装器系统 (functions/bin/)

**包装器特性**:
- 自动路径解析
- 错误处理和回退
- 调试模式支持
- 版本信息跟踪

**生成机制**:
- 基于模板自动生成
- 统一的错误处理逻辑
- 路径验证和安全检查

## 开发和维护

### 8. 构建流程

**构建命令**:
```bash
cd functions/agents/sh-ai
./scripts/build.sh
```

**构建步骤**:
1. 创建输出目录
2. 生成文件头和版本信息
3. 按依赖顺序合并核心模块
4. 自动发现并合并业务模块
5. 添加 argc 评估入口
6. 语法检查和验证
7. 生成标准文件 (functions.json, tools.txt)
8. 创建符号链接

**验证检查**:
- Bash 语法检查
- argc 兼容性验证
- JSON 格式验证
- 函数统计和报告

### 9. 测试和调试

**调试模式**:
```bash
export SH_AI_DEBUG=true
export SH_AI_VERBOSE=true
```

**测试脚本**:
- 单元测试 (各模块独立测试)
- 集成测试 (端到端流程)
- 兼容性测试 (不同环境)
- 性能测试 (响应时间)

### 10. 扩展和定制

**添加新功能模块**:
1. 在 `src/modules/` 创建新文件
2. 添加 argc 注释
3. 实现业务逻辑
4. 运行构建脚本
5. 测试和验证

**自定义设备类型**:
1. 扩展 `device_detect.sh`
2. 添加检测规则
3. 更新缓存逻辑
4. 测试检测准确性

## 性能和优化

### 11. 性能特性

**响应速度优化**:
- 禁用 RAG 查询 (减少 200ms 延迟)
- 精简指令 (减少 60% token 消耗)
- 智能缓存 (24小时设备类型缓存)
- 连接复用 (ControlMaster)

**内存管理**:
- 输出缓冲区大小限制 (1000 条消息)
- 自动缓冲区清理
- 内存泄漏防护

**错误处理**:
- 多层错误检查
- 优雅降级机制
- 详细错误报告
- 自动恢复策略

### 12. 安全考虑

**命令安全**:
- 危险命令检测和警告
- 用户确认机制
- 命令白名单/黑名单
- 参数注入防护

**连接安全**:
- SSH 密钥验证
- 连接超时控制
- 安全的连接清理
- 权限检查

## 总结

SH-AI 项目采用现代化的模块化架构，通过智能的构建系统和严格的标准化流程，实现了高性能、高可靠性的 AI 增强型 SSH 管理工具。项目的设计充分考虑了可扩展性、可维护性和用户体验，为复杂的远程设备管理提供了简洁而强大的解决方案。

**关键优势**:
- 📦 模块化设计，易于扩展和维护
- 🚀 高性能优化，快速响应
- 🛡️ 多层安全防护
- 🤖 AI 深度集成
- 📊 标准化输出格式
- 🔧 自动化构建和部署

该架构为未来的功能扩展和性能优化奠定了坚实的基础。