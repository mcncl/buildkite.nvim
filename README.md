# buildkite.nvim

[![Latest Release](https://img.shields.io/github/v/release/mcncl/buildkite.nvim?style=flat-square)](https://github.com/mcncl/buildkite.nvim/releases)
[![ZeroVer](https://img.shields.io/badge/version-0ver-blue?style=flat-square)](https://0ver.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Neovim](https://img.shields.io/badge/NeoVim-%2357A143.svg?&style=flat-square&logo=neovim&logoColor=white)](https://neovim.io/)

A Neovim plugin for interacting with Buildkite CI/CD pipelines directly from your editor.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
  - [Using lazy.nvim](#using-lazynvim)
  - [Using packer.nvim](#using-packernvim)
  - [Using vim-plug](#using-vim-plug)
- [Configuration](#configuration)
- [Usage](#usage)
- [Contributing](#contributing)
- [License](#license)

## Features

- 🚀 View build status for current git branch
- 🔧 Configure multiple Buildkite organizations with easy switching
- 📊 List recent builds for any branch
- 🌐 Open builds in browser
- 🔄 Rebuild failed builds with instant status updates
- ⚙️ Per-project pipeline configuration
- 🎯 Auto-detect pipeline based on git repository
- 📱 Statusline integration (lualine, etc.)
- ⌨️ Customizable keymaps
- 🔍 Built-in debugging tools

## Requirements

- Neovim >= 0.7.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- Buildkite API token(s)

## Installation

### Using `lazy.nvim`

**Basic Setup:**
```lua
{
  "mcncl/buildkite.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("buildkite").setup()
  end,
}
```

**Version Pinning:**
```lua
{
  "mcncl/buildkite.nvim",
  version = "*",        -- Use latest release (recommended for stability)
  -- version = "v0.1.0", -- Pin to specific version
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("buildkite").setup()
  end,
}
```

> **Note on Versions:**
> - No `version` specified = latest commit on main branch (bleeding edge)
> - `version = "*"` = latest stable release (recommended)
> - `version = "v0.1.0"` = specific version (maximum stability)

**Advanced Setup with Lazy Loading and Custom Keys:**
```lua
{
  "mcncl/buildkite.nvim",
  version = "*",        -- Use latest release (recommended)
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "Buildkite" }, -- Load only when :Buildkite command is used
  keys = { -- Load when these keys are pressed
    { "<leader>bc", function() require("buildkite.commands").show_current_build() end, desc = "Current build" },
    { "<leader>bl", function() require("buildkite.commands").show_builds() end, desc = "List builds" },
    { "<leader>bo", function() require("buildkite.commands").open_build_url() end, desc = "Open build" },
    { "<leader>br", function() require("buildkite.commands").rebuild_current_build() end, desc = "Rebuild build" },
    { "<leader>bp", function() require("buildkite.commands").set_pipeline() end, desc = "Set pipeline" },
    { "<leader>bs", function() require("buildkite.commands").switch_organization() end, desc = "Switch org" },
    { "<leader>bbs", function() require("buildkite.commands").set_branch() end, desc = "Set branch" },
    { "<leader>bbu", function() require("buildkite.commands").unset_branch() end, desc = "Unset branch" },
    { "<leader>bbi", function() require("buildkite.commands").show_branch_info() end, desc = "Branch info" },
  },
  config = function()
    require("buildkite").setup({
      organizations = {
        ["my-company"] = {
          token = vim.env.BUILDKITE_TOKEN,
        },
        ["client-company"] = {
          token = vim.env.BUILDKITE_TOKEN_CLIENT,
          repositories = {"client-app", "client-api"},
        },
      },
      current_organization = "my-company",
      keymaps = { enabled = false }, -- Using custom keys above
      auto_setup = { enabled = true, suggest_pipeline = true },
    })
  end,
}
```

> **Note:** Lazy loading improves startup time by only loading the plugin when needed. The statusline integration will still work automatically once loaded.

### Using `packer.nvim`

```lua
use {
  "mcncl/buildkite.nvim",
  requires = { "nvim-lua/plenary.nvim" },
  tag = "*",        -- Use latest release (recommended)
  -- tag = "v0.1.0", -- Pin to specific version
  config = function()
    require("buildkite").setup()
  end,
}
```

### Using `vim-plug`

```lua
Plug 'nvim-lua/plenary.nvim'
Plug 'mcncl/buildkite.nvim', { 'tag': '*' }  " Latest release
" Plug 'mcncl/buildkite.nvim', { 'tag': 'v0.1.0' }  " Specific version
```

## Getting a Buildkite API Token

1. Go to [Buildkite Personal Access Tokens](https://buildkite.com/user/api-access-tokens)
2. Click "New API Access Token"
3. Give it a name (e.g., "Neovim Plugin")
4. Select the following scopes:
   - `read_builds`
   - `read_pipelines`
   - `read_organizations`
   - `write_builds` (optional, for rebuilding)
5. Click "Create Token"
6. Copy the token for use in configuration

## Quick Start

> **💡 Version Tip:** For stability, pin to a release version in your plugin manager: `version = "*"` (latest release) or `version = "v0.1.0"` (specific version).

1. **Add your first organization:**
   ```vim
   :Buildkite org add
   ```
   Enter your organization name and API token. This will be set as your current organization.

2. **Set up a pipeline for your project:**
   ```vim
   :Buildkite pipeline set
   ```
   The plugin will fetch your pipelines and try to auto-detect the right one based on your git repository.

3. **Check your current build:**
   ```vim
   :Buildkite build current
   ```

That's it! The plugin will remember your organization and pipeline settings per project.

## Configuration

The plugin can be configured during setup or will use sensible defaults.

### Basic Setup

```lua
require("buildkite").setup({
  organizations = {
    ["my-company"] = {
      token = "bkua_your_token_here",
    },
  },
  current_organization = "my-company",
})
```

### Full Configuration

```lua
require("buildkite").setup({
  organizations = {
    ["my-company"] = {
      token = vim.env.BUILDKITE_TOKEN, -- Use environment variable
      repositories = {}, -- Optional: filter to specific repos
    },
    ["client-org"] = {
      token = vim.env.BUILDKITE_TOKEN_CLIENT,
      repositories = {"client-app", "client-api"},
    },
  },
  current_organization = "my-org",
  api = {
    endpoint = "https://api.buildkite.com/v2",
    timeout = 10000,
  },
  ui = {
    icons = {
      passed = "✓",
      failed = "✗",
      running = "●",
      scheduled = "○",
      canceled = "◎",
      skipped = "◌",
      blocked = "⏸",
    },
  },
  keymaps = {
    enabled = true,
    prefix = "<leader>bk",
    mappings = {
      current_build = "c",
      current_pipeline = "cp",
      list_builds = "l",
      open_build = "o",
      rebuild_build = "r",
      set_pipeline = "p",
      org_list = "ol",
      org_switch = "os",
      branch_set = "bs",
      branch_unset = "bu",
      branch_info = "bi",
  }
  },
  auto_setup = {
    enabled = true,
    suggest_pipeline = true,
  },
  cache = {
    build_duration = 60000, -- Cache build status for 60 seconds (in milliseconds)
  }
})
```

## Commands

### Organization Management

```vim
:Buildkite org add                    " Add a new organization
:Buildkite org remove [name]          " Remove an organization
:Buildkite org list                   " List all organizations
:Buildkite org switch [name]          " Switch current organization
:Buildkite org current               " Show current organization
```

### Pipeline Management

```vim
:Buildkite pipeline set [name]        " Set pipeline for current project
:Buildkite pipeline unset             " Remove pipeline for current project
:Buildkite pipeline info              " Show current project's pipeline
```

### Branch Management

```vim
:Buildkite branch set [name]          " Set manual branch override
:Buildkite branch unset               " Remove manual branch override
:Buildkite branch info                " Show current branch information
```

### Build Information

```vim
:Buildkite build current              " Show current branch build status
:Buildkite build list [branch] [n]    " List recent builds (default: 10)
:Buildkite build open                 " Open current build in browser
:Buildkite build refresh              " Refresh current build status (clears cache)
:Buildkite build rebuild              " Rebuild the most recent build (updates status instantly)
```

### Debug Commands

```vim
:Buildkite debug config               " Show configuration
:Buildkite debug reset                " Reset all configuration
```

## Keymaps

### Default Keymaps

With the default keymap prefix `<leader>bk`:

- `<leader>bkc` - Show current build
- `<leader>bkcp` - Show current pipeline
- `<leader>bkl` - List builds
- `<leader>bko` - Open build in browser
- `<leader>bkr` - Rebuild current build
- `<leader>bkp` - Set pipeline
- `<leader>bkol` - List organizations
- `<leader>bkos` - Switch organization
- `<leader>bkbs` - Set branch
- `<leader>bkbu` - Unset branch
- `<leader>bkbi` - Show branch info

### Custom Keymaps

You can disable the default keymaps and define your own:

```lua
require("buildkite").setup({
  keymaps = { enabled = false },
  -- ... other config
})

-- Then define your own keymaps
vim.keymap.set('n', '<leader>bc', function() require("buildkite.commands").show_current_build() end, { desc = "Buildkite: Current build" })
vim.keymap.set('n', '<leader>bl', function() require("buildkite.commands").show_builds() end, { desc = "Buildkite: List builds" })
vim.keymap.set('n', '<leader>bs', function() require("buildkite.commands").set_branch() end, { desc = "Buildkite: Set branch" })
vim.keymap.set('n', '<leader>bu', function() require("buildkite.commands").unset_branch() end, { desc = "Buildkite: Unset branch" })
vim.keymap.set('n', '<leader>bi', function() require("buildkite.commands").show_branch_info() end, { desc = "Buildkite: Branch info" })
-- ... add more as needed
```

Or use them directly in your plugin manager's `keys` configuration (see lazy.nvim advanced setup example above).

## Multiple Organizations

Since each API token only works with one Buildkite organization, the plugin supports multiple organizations with easy switching:

```lua
organizations = {
  ["work-org"] = {
    token = "bkua_work_token_here",
  },
  ["personal-org"] = {
    token = "bkua_personal_token_here",
    repositories = {"my-project"},
  },
},
current_organization = "work-org",
```

Use `:Buildkite org switch` to change between them. All pipeline and build operations use the currently active organization.

## Performance and Caching

The plugin caches build status to avoid excessive API calls that could slow down your editor. By default:

- **Build status is cached for 60 seconds**
- **Cache is per-branch and per-pipeline**
- **Lualine integration uses cached data** (no performance impact)

You can configure the cache duration:

```lua
require("buildkite").setup({
  cache = {
    build_duration = 30000, -- Cache for 30 seconds
  },
})
```

To manually refresh the build status:
```vim
:Buildkite build refresh
```

This clears the cache and fetches fresh data from the Buildkite API.

## Statusline Integration

### Lualine

Add this component to your lualine configuration. The integration is performant thanks to built-in caching:

```lua
require('lualine').setup {
  sections = {
    lualine_c = {
      -- ... other components
      {
        function()
          local buildkite = require("buildkite")
          local build, err = buildkite.get_current_build()
          if build and not err then
            local config = buildkite.get_config()
            local icon = config.ui.icons[build.state] or "?"
            return icon .. " " .. build.state .. " #" .. build.number
          elseif err == "Loading..." then
            return "⏳ Loading..."
          end
          return ""
        end,
        cond = function()
          return require("buildkite.git").is_git_repo()
        end,
        color = function()
          local buildkite = require("buildkite")
          local build, err = buildkite.get_current_build()
          if build and not err then
            if build.state == "passed" then
              return { fg = "#50fa7b" } -- green
            elseif build.state == "failed" then
              return { fg = "#ff5555" } -- red
            elseif build.state == "running" then
              return { fg = "#f1fa8c" } -- yellow
            elseif build.state == "scheduled" then
              return { fg = "#8be9fd" } -- cyan
            elseif build.state == "blocked" then
              return { fg = "#ffb86c" } -- orange
            elseif build.state == "canceled" then
              return { fg = "#6272a4" } -- gray
            end
          end
          return { fg = "#6272a4" } -- gray
        end,
      },
    },
  },
}
```

### Other Statuslines

For other statusline plugins, use the core function (cached automatically):

```lua
local buildkite = require("buildkite")
local build, err = buildkite.get_current_build()
if build and not err then
  local config = buildkite.get_config()
  local icon = config.ui.icons[build.state] or "?"
  -- Add icon .. " " .. build.state .. " #" .. build.number to your statusline
end
```

**Note:** The `get_current_build()` function uses intelligent caching, so it's safe to call frequently in statuslines without performance concerns.

## Project Configuration

The plugin automatically saves configurations per project in your Neovim data directory:

- Global config: `~/.local/share/nvim/buildkite.nvim/config.json`
- Project configs: `~/.local/share/nvim/buildkite.nvim/projects/`

Each project gets its own configuration based on the working directory path, including:
- Pipeline configuration (organization and pipeline slug)
- Manual branch override (if set)

### Manual Branch Override

By default, the plugin uses your Git branch to determine which Buildkite builds to show. However, you can override this behavior:

**Use Cases:**
- Working in a non-Git directory but wanting to monitor builds
- Local branch name differs from the Buildkite branch name
- Monitoring a different branch while working on another
- Working in detached HEAD state

**Commands:**
```vim
:Buildkite branch set main            " Monitor 'main' branch builds
:Buildkite branch info               " Show current effective branch
:Buildkite branch unset              " Remove override, use Git branch
```

The manual branch override is saved per-project, so different projects can have different branch settings.

## Environment Variables

It's recommended to use environment variables for your API tokens:

```bash
export BUILDKITE_TOKEN="bkua_your_token_here"
export BUILDKITE_TOKEN_CLIENT="bkua_client_token_here"
```

Then in your config:

```lua
organizations = {
  ["my-company"] = {
    token = vim.env.BUILDKITE_TOKEN,
  },
  ["client-company"] = {
    token = vim.env.BUILDKITE_TOKEN_CLIENT,
  },
},
```

## Health Check

Check if everything is configured correctly:

```vim
:checkhealth buildkite
```

## Troubleshooting

### Common Issues

1. **"No organizations configured"**
   - Run `:Buildkite org add` to add your first organization

2. **"No pipeline configured"**
   - Run `:Buildkite pipeline set` in your project directory

3. **"API request failed"**
   - Check your API token has the correct scopes
   - Verify the organization name is correct
   - Check your internet connection and API endpoint availability

4. **"Could not determine current git branch"**
   - Make sure you're in a git repository
   - Check that git is available in your PATH
   - Use `:Buildkite branch set <branch_name>` to manually specify a branch

### Debug Information

Use the debug commands for troubleshooting:

```vim
:Buildkite debug config              " Show current configuration
```

## Releases and Version Management

### Stable Releases

This plugin follows [ZeroVer](https://0ver.org/) (0-based versioning). Each release is tagged and available on the [Releases page](https://github.com/mcncl/buildkite.nvim/releases).

**Version Types:**
- **Minor** (v0.2.0): New features, may include breaking changes
- **Patch** (v0.1.1): Bug fixes, backward compatible
- **Pre-release** (v0.2.0-beta.1): Testing versions

### Installation Strategies

**For Production Use (Recommended):**
```lua
{
  "mcncl/buildkite.nvim",
  version = "*",  -- Always use latest stable release
  dependencies = { "nvim-lua/plenary.nvim" },
}
```

**For Testing New Features:**
```lua
{
  "mcncl/buildkite.nvim",
  -- No version specified = latest commit (may be unstable)
  dependencies = { "nvim-lua/plenary.nvim" },
}
```

**For Maximum Stability:**
```lua
{
  "mcncl/buildkite.nvim",
  version = "v0.1.0",  -- Pin to specific tested version
  dependencies = { "nvim-lua/plenary.nvim" },
}
```

### Release Notes

Check the [Releases page](https://github.com/mcncl/buildkite.nvim/releases) for:
- New features and improvements
- Bug fixes
- Breaking changes
- Migration guides

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) file for details.
