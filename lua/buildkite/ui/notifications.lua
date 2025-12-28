local M = {}

---Notify with Buildkite prefix
---@param msg string
---@param level number|nil vim.log.levels
function M.notify(msg, level)
  local config = require("buildkite.config").get()

  if not config.notifications.enabled then
    return
  end

  level = level or vim.log.levels.INFO

  if level < config.notifications.level then
    return
  end

  vim.notify("[Buildkite] " .. msg, level)
end

---Show info notification
---@param msg string
function M.info(msg)
  M.notify(msg, vim.log.levels.INFO)
end

---Show warning notification
---@param msg string
function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

---Show error notification
---@param msg string
function M.error(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

---Show debug notification (only if level allows)
---@param msg string
function M.debug(msg)
  M.notify(msg, vim.log.levels.DEBUG)
end

return M
