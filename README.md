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

This project depends on the following open-source projects:

- [sigoden/aichat](https://github.com/sigoden/aichat) - MIT License
- [sigoden/llm-functions](https://github.com/sigoden/llm-functions) - MIT License
- [sigoden/argc](https://github.com/sigoden/argc) - MIT License

## Installation

### Prerequisites

- Bash shell
- Git
- AIChat installed and configured
- SSH client

### Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/sh-ai.git
   cd sh-ai
   ```

2. **Run the build script**
   ```bash
   ./scripts/build.sh
   ```

3. **Configure AIChat**
   - Ensure AIChat is installed: `aichat --version`
   - Set up your LLM API keys if required

4. **Use with AIChat**
   ```bash
   aichat --agent sh-ai --model ollama:qwen3:4b

   ```

## Usage

See the documentation in `doc/SH-AI_项目架构和索引.md` for detailed usage instructions.


## 项目演示

<video src="https://github.com/user-attachments/assets/4831174c-0d23-4743-bc2c-4d3f211b6278" controls width="100%"></video>

## Contributing

Contributions are welcome! Please read the contributing guidelines before submitting pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

The dependencies listed above are also licensed under the MIT License, ensuring compatibility.