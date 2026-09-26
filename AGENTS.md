# home-manager-base - AGENTS.md

## Overview

`home-manager-base` provides Home Manager configurations for the nixos-reactor project.
It includes modules for user-level settings, applications, services, and AI/MCP integration.

This submodule is designed to be composable and machine-agnostic, allowing the same user configuration
to be applied across different machines (e.g., WSL, native Linux, Docker) with platform-specific adaptations.

## Structure

The project is organized into:

- `modules/`: Contains Home Manager modules organized by category.
    - `ai/`: AI integration, including agents, providers, prompts, and skills.
    - `cli-tools/`: Command-line interface tools and enhancements.
    - `connection/`: Network and connection-related configurations.
    - `core/`: Fundamental Home Manager settings and utilities.
    - `desktop/`: Desktop environment configurations (e.g., GNOME, KDE).
    - `documentation/`: Tools for generating and viewing documentation.
    - `editor/`: Code editor configurations (e.g., VS Code, Neovim).
    - `environments/`: Development environment setups (e.g., Python, Node.js).
    - `ide/`: Integrated Development Environment configurations.
    - `keyring/`: Secret management and keyring integrations.
    - `languages/`: Programming language-specific configurations.
    - `mcp/`: Model Context Protocol server and client configurations.
    - `misc/`: Miscellaneous utilities and tools.
    - `networks/`: Network configuration and services.
    - `platform-config/`: Platform-specific configurations (used via `myHomePlatform`).
    - `secrets-store/`: Secure secret management using SOPS and age.
    - `shell/`: Shell environment and prompt configurations.
    - `shell-prompt/`: Custom shell prompt themes and configurations.
    - `task/`: Task management and productivity tools.
    - `terminal-emulator/`: Terminal emulator configurations.
    - `vcs/`: Version control system integrations (e.g., Git, GitHub).

- `platform/`: Contains platform-specific configurations that are imported via `myHomePlatform`.
    - `native-linux.nix`: Configuration for native Linux systems.
    - `docker.nix`: Configuration for Docker containers.
    - `wsl.nix`: Configuration for Windows Subsystem for Linux.

- `flake.nix`: The flake definition for this submodule, defining inputs, outputs, and the `createModules` function.

- `tests/`: Tests for the Home Manager configuration, including flake checks and module tests.

## Development Guidelines

### Adding a New Home Manager Module

1. **Choose the appropriate category**: Place your module in the relevant subdirectory under `modules/`.
   - If the category doesn't exist, create a new directory (e.g., `modules/my-new-category/`).
   - Follow the existing naming convention (lowercase, hyphens for separation).

2. **Module format**: Each module should be a Nix file (default.nix or a file with a descriptive name) that exports an attribute set following the Home Manager module format:

   ```nix
   { config, pkgs, lib, ... }:
   {
     options = {
       # Declare options here if needed
     };
     config = {
       # Implementation here
     };
   }
   ```

3. **Using lib**: Utilize the `lib` module for common patterns:
   - `mkEnableOption`: To create a boolean enable option.
   - `mkIf`: To conditionally enable configuration.
   - `mkDefault`: To set default values that can be overridden.
   - `mkForce`: To override configuration from other modules.

4. **Options**: If your module introduces new options, declare them under `options`. Use meaningful names and descriptions.

5. **Imports**: If your module depends on other modules, add them to the `imports` list.

### Platform-Specific Configurations

- For configurations that vary by platform (e.g., WSL vs. native Linux), use the `platform/` directory.
- These are imported via `myHomePlatform` in the machine's configuration (see the root AGENTS.md for examples).

### Testing

- Write tests for your modules in the `tests/` directory.
- The test framework uses `nixpkgs.fake` and `home-manager` to evaluate modules.
- Follow the existing test patterns in `tests/modules/`.

### Nix Techniques

- Follow the Nix techniques used in the project: Flakes, home-manager modules, and option declarations.
- Prefer using `with lib;` and `with lib.types;` for clarity.
- Use `rec` for records when needed.
- Avoid global mutations; prefer functional composition.

## Critical Notes

- This submodule is used as an input in the main flake (nixos-reactor) via `home-manager-base.url = "git+file:./submodules/home-manager-base";`.
- Changes to this submodule may require updating the flake.lock in the main repository and any dependent submodules.
- The `createHomeModules` function in the main flake is used to generate machine-specific Home Manager configurations from this base.
- When adding new modules, ensure they are compatible with the `createModules` function in `flake.nix`.
- Always test your changes by running the relevant checks (see the `checks` attribute in `flake.nix`).
- For AI and MCP integration, refer to the `ai/` and `mcp/` modules as examples of complex integrations.

## AI/MCP Integration Patterns

The `ai/` module provides a pattern for integrating AI services and MCP servers:

### AI Provider Configuration

- The `ai/default.nix` module defines an `options.my.home.ai` structure that allows configuring multiple AI providers.
- Each provider can have a name, URL, and a list of models with associated roles (chat, edit, apply, autocomplete, embed, rerank).
- The module uses `submodule` to define nested options for providers and models.

### Example AI Configuration (from a machine's configuration.nix)

```nix
my.home.ai = {
  enable = true;
  localOnly = false;
  providers = [
    {
      name = "ollama";
      url = "http://localhost:11434";
      models = [
        { model = "gemma3:12b"; roles = [ "chat" "edit" "apply" ]; }
        { model = "deepseek-coder-v2:16b"; roles = [ "autocomplete" ]; }
      ];
    };
  ];
};
```

### MCP Server Configuration

- The `mcp/` module configures MCP servers and clients.
- MCP servers are defined per environment (global, vscode, documentAnalysis, etc.) using preset servers.
- The VS Code integration is handled in the `ai/default.nix` module, where MCP server access is configured for the GitHub Copilot extension.

### Example MCP Configuration

```nix
my.home.mcp.servers = {
  global = { presetServers = { devtools.enable = true; }; };
  vscode = global;
  documentAnalysis = {
    presetServers = {
      markitdown.enable = true;
      excel.enable = true;
    };
  };
};
```

