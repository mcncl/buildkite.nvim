# buildkite.nvim

A Neovim plugin for interacting with [Buildkite](https://buildkite.com) pipelines.

## Features

- **Multi-organization support** - Manage multiple Buildkite organizations with token precedence (env vars → keychain → config file)
- **Pipeline linting** - Validate pipeline YAML against the Buildkite schema using treesitter
- **Build management** - List recent builds, trigger new builds from Neovim
- **Local step execution** - Run pipeline steps locally using `buildkite-agent`
- **Auto-detection** - Automatically detects pipeline slug from git remote or directory name

## Requirements

- Neovim >= 0.9.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- Treesitter YAML parser (`:TSInstall yaml`) - for linting
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional) - enhanced picker UI
- `buildkite-agent` (optional) - for local step execution

## Installation

### lazy.nvim

```lua
{
  "mcncl/buildkite.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("buildkite").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "mcncl/buildkite.nvim",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("buildkite").setup()
  end,
}
```

## Configuration

```lua
require("buildkite").setup({
  -- Auto-lint pipeline files on save
  lint_on_save = true,

  -- Default organization (optional, can also be set via config file)
  default_org = nil,

  -- Path to config file
  config_path = vim.fn.stdpath("config") .. "/buildkite.json",

  -- Keymaps (set to false to disable)
  keymaps = {
    lint = "<leader>bl",
    run_step = "<leader>br",
    builds = "<leader>bb",
  },

  -- Notifications
  notifications = {
    enabled = true,
    level = vim.log.levels.INFO,
  },
})
```

## Commands

All commands follow the pattern `:Buildkite <noun> <verb>`:

### Organization Management

| Command | Description |
|---------|-------------|
| `:Buildkite org add <slug>` | Add an organization (prompts for API token) |
| `:Buildkite org switch` | Switch between configured organizations |
| `:Buildkite org list` | List all configured organizations |
| `:Buildkite org info` | Show current organization info |

### Pipeline Operations

| Command | Description |
|---------|-------------|
| `:Buildkite pipeline lint` | Lint the current pipeline file |
| `:Buildkite pipeline set <slug>` | Override the auto-detected pipeline slug |
| `:Buildkite pipeline info` | Show detected pipeline info |

### Build Management

| Command | Description |
|---------|-------------|
| `:Buildkite build list` | Show recent builds (opens picker) |
| `:Buildkite build trigger [branch]` | Trigger a new build |

### Local Execution

| Command | Description |
|---------|-------------|
| `:Buildkite step run` | Run the step under cursor locally |
| `:Buildkite step select` | Select a step to run locally |

## Credential Management

API tokens are loaded with the following precedence:

1. **Environment variables** (highest priority)
   - `BUILDKITE_TOKEN_<ORG_SLUG>` (e.g., `BUILDKITE_TOKEN_MY_ORG`)
   - `BUILDKITE_API_TOKEN` (generic fallback)

2. **macOS Keychain** (if available)
   - Stored via `:Buildkite org add` with keychain option

3. **Config file** (lowest priority)
   - `~/.config/nvim/buildkite.json` by default

## Pipeline Detection

The plugin auto-detects the pipeline slug in this order:

1. Manual override via `:Buildkite pipeline set`
2. Project-local `.buildkite.lua` file with `return { pipeline = "slug" }`
3. Repository name from git remote
4. Current directory name

## Health Check

Run `:checkhealth buildkite` to verify your setup.

## License

MIT
