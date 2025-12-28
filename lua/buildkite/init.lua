local M = {}

M._initialized = false

---@param opts BuildkiteConfig|nil
function M.setup(opts)
  if M._initialized then
    return
  end

  local config = require("buildkite.config")
  config.setup(opts)

  local options = config.get()

  -- Register commands
  require("buildkite.commands").setup()

  -- Setup keymaps if enabled
  if options.keymaps then
    M._setup_keymaps(options.keymaps)
  end

  -- Setup auto-lint on save if enabled
  if options.lint_on_save then
    M._setup_lint_autocmd()
  end

  M._initialized = true
end

---@param keymaps BuildkiteKeymaps
function M._setup_keymaps(keymaps)
  local function map(key, cmd, desc)
    if key then
      vim.keymap.set("n", key, cmd, { desc = desc })
    end
  end

  map(keymaps.lint, "<cmd>Buildkite pipeline lint<cr>", "Buildkite: Lint pipeline")
  map(keymaps.run_step, "<cmd>Buildkite step run<cr>", "Buildkite: Run step at cursor")
  map(keymaps.builds, "<cmd>Buildkite build list<cr>", "Buildkite: Show builds")
end

function M._setup_lint_autocmd()
  local group = vim.api.nvim_create_augroup("BuildkiteLint", { clear = true })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = {
      "*.buildkite.yml",
      "*.buildkite.yaml",
      ".buildkite/pipeline.yml",
      ".buildkite/pipeline.yaml",
      "buildkite.yml",
      "buildkite.yaml",
    },
    callback = function()
      require("buildkite.lint").lint_buffer()
    end,
  })
end

return M
