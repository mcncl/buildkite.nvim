local M = {}

local health = vim.health

function M.check()
  health.start("buildkite.nvim")

  -- Check Neovim version
  if vim.fn.has("nvim-0.9.0") == 1 then
    health.ok("Neovim version >= 0.9.0")
  else
    health.error("Neovim version 0.9.0+ required")
  end

  -- Check plenary.nvim
  local plenary_ok = pcall(require, "plenary")
  if plenary_ok then
    health.ok("plenary.nvim is installed")
  else
    health.error("plenary.nvim is not installed", {
      "Install with your package manager:",
      "  { 'nvim-lua/plenary.nvim' }",
    })
  end

  -- Check YAML treesitter parser
  local lint = require("buildkite.lint")
  if lint.has_yaml_parser() then
    health.ok("YAML treesitter parser is installed")
  else
    health.warn("YAML treesitter parser is not installed", {
      "Required for pipeline linting",
      "Install with: :TSInstall yaml",
    })
  end

  -- Check buildkite-agent (optional)
  local runner = require("buildkite.runner")
  if runner.has_agent() then
    local version = vim.fn.system("buildkite-agent --version 2>/dev/null")
    health.ok("buildkite-agent is installed: " .. vim.trim(version):gsub("\n.*", ""))
  else
    health.info("buildkite-agent is not installed (optional, for future features)")
  end

  -- Check telescope (optional)
  local telescope_ok = pcall(require, "telescope")
  if telescope_ok then
    health.ok("telescope.nvim is installed (enhanced picker)")
  else
    health.info("telescope.nvim is not installed (using vim.ui.select)")
  end

  -- Check organization configuration
  local orgs = require("buildkite.organizations")
  local current_org = orgs.get_current()
  local org_list = orgs.list()

  if #org_list > 0 then
    health.ok(string.format("%d organization(s) configured", #org_list))
    if current_org then
      health.ok("Current organization: " .. current_org)
    end
  else
    health.warn("No organizations configured", {
      "Add an organization with: :BuildkiteAddOrg <slug>",
    })
  end

  -- Check credentials for current org
  if current_org then
    local credentials = require("buildkite.credentials")
    local cred, _ = credentials.get_token(current_org)
    if cred then
      health.ok("Credentials found for '" .. current_org .. "' (source: " .. cred.source .. ")")
    else
      health.error("No credentials found for organization '" .. current_org .. "'", {
        "Set BUILDKITE_API_TOKEN environment variable, or",
        "Run :BuildkiteAddOrg " .. current_org,
      })
    end
  end

  -- Check pipeline detection
  local pipeline = require("buildkite.pipeline")
  local slug = pipeline.get_slug()
  if slug then
    health.ok("Detected pipeline: " .. slug)
  else
    health.info("No pipeline detected (not in a git repository or project)")
  end

  -- Check config file
  local config = require("buildkite.config").get()
  if vim.fn.filereadable(config.config_path) == 1 then
    health.ok("Config file exists: " .. config.config_path)
  else
    health.info("No config file (will be created when adding an organization)")
  end
end

return M
