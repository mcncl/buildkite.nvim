---@class BuildkiteConfig
---@field lint_on_save boolean Auto-lint pipeline files on save
---@field default_org string|nil Default organization slug
---@field config_path string Path to config file
---@field keymaps BuildkiteKeymaps|false Keymap configuration or false to disable
---@field notifications BuildkiteNotifications Notification settings

---@class BuildkiteKeymaps
---@field lint string|false Keymap to lint current buffer
---@field run_step string|false Keymap to run step under cursor
---@field builds string|false Keymap to show builds

---@class BuildkiteNotifications
---@field enabled boolean Enable notifications
---@field level integer Minimum log level (vim.log.levels)

local M = {}

---@type BuildkiteConfig
M.defaults = {
  lint_on_save = true,
  default_org = nil,
  config_path = vim.fn.stdpath("config") .. "/buildkite.json",
  keymaps = {
    lint = "<leader>bl",
    run_step = "<leader>br",
    builds = "<leader>bb",
  },
  notifications = {
    enabled = true,
    level = vim.log.levels.INFO,
  },
}

---@type BuildkiteConfig
M.options = {}

---@param opts BuildkiteConfig|nil
---@return BuildkiteConfig
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  return M.options
end

---@return BuildkiteConfig
function M.get()
  return M.options
end

return M
