# sh-ai

aichat for shell - AI-enhanced SSH management tool

## Description

SH-AI is an AI-enhanced SSH management tool that runs within the AIChat process, providing intelligent device detection, command generation, and execution through a modular architecture.

## Features

- 🤖 AI-enhanced SSH connection management
- 🔍 Automatic device type detection and caching
- 📝 Unified Markdown format output
- 🔄 Dual-mode support (AIChat/CLI)
- 🛡️ Secure command execution mechanism
- 📊 Structured JSON responses

## Dependencies

- [sigoden/aichat](https://github.com/sigoden/aichat)
- [sigoden/llm-functions](https://github.com/sigoden/llm-functions)
- [sigoden/argc](https://github.com/sigoden/argc)

## Installation

1. Clone this repository
2. Run the build script: `./scripts/build.sh`
3. Use with AIChat: `aichat --agent sh-ai --session work`

## Usage

See the documentation in `doc/SH-AI_项目架构和索引.md` for detailed usage instructions.

## License

MIT