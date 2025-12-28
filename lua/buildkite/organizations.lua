local M = {}

-- In-memory cache of current org (overrides config file)
local current_org_override = nil

---Get the current organization slug
---@return string|nil
function M.get_current()
  -- Check override first
  if current_org_override then
    return current_org_override
  end

  -- Check config for default_org
  local config = require("buildkite.config").get()
  if config.default_org then
    return config.default_org
  end

  -- Check config file for current_org
  local config_path = config.config_path
  if vim.fn.filereadable(config_path) == 1 then
    local ok, content = pcall(vim.fn.readfile, config_path)
    if ok then
      local json_ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
      if json_ok and data and data.current_org then
        return data.current_org
      end
    end
  end

  return nil
end

---Set the current organization (session override)
---@param org_slug string
function M.set_current(org_slug)
  current_org_override = org_slug
  vim.notify("Switched to organization: " .. org_slug, vim.log.levels.INFO)
end

---Add or update an organization
---@param org_slug string Organization slug
function M.add(org_slug)
  if not org_slug or org_slug == "" then
    vim.notify("Organization slug is required", vim.log.levels.ERROR)
    return
  end

  vim.ui.input({
    prompt = "Enter API token for '" .. org_slug .. "': ",
  }, function(token)
    if not token or token == "" then
      vim.notify("Cancelled", vim.log.levels.INFO)
      return
    end

    -- Validate token first
    vim.notify("Validating token...", vim.log.levels.INFO)
    require("buildkite.api").validate_token(org_slug, token, function(valid, message)
      if not valid then
        vim.notify("Token validation failed: " .. message, vim.log.levels.ERROR)
        return
      end

      -- Ask where to store
      local storage_options = { "Config file" }
      if vim.fn.has("mac") == 1 then
        table.insert(storage_options, 1, "macOS Keychain (recommended)")
      end

      vim.ui.select(storage_options, {
        prompt = "Where to store the token?",
      }, function(choice)
        if not choice then
          vim.notify("Cancelled", vim.log.levels.INFO)
          return
        end

        local credentials = require("buildkite.credentials")
        local success, err

        if choice:match("Keychain") then
          success, err = credentials.store_in_keychain(org_slug, token)
          -- Also store org metadata (without token) in config
          if success then
            credentials.store_in_config(org_slug, "", {})
          end
        else
          success, err = credentials.store_in_config(org_slug, token)
        end

        if success then
          vim.notify("Organization '" .. org_slug .. "' added successfully", vim.log.levels.INFO)
          -- Set as current if first org
          if not M.get_current() then
            M.set_current(org_slug)
          end
        else
          vim.notify("Failed to store credentials: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

---Switch to a different organization
function M.switch()
  local available = require("buildkite.credentials").list_available()
  local orgs = vim.tbl_keys(available)

  -- Filter out the _default pseudo-org
  orgs = vim.tbl_filter(function(org)
    return org ~= "_default"
  end, orgs)

  if #orgs == 0 then
    vim.notify("No organizations configured. Run :BuildkiteAddOrg <slug> first.", vim.log.levels.WARN)
    return
  end

  if #orgs == 1 then
    M.set_current(orgs[1])
    return
  end

  local current = M.get_current()

  vim.ui.select(orgs, {
    prompt = "Select organization:",
    format_item = function(org)
      if org == current then
        return org .. " (current)"
      end
      return org
    end,
  }, function(choice)
    if choice then
      M.set_current(choice)
    end
  end)
end

---List all configured organizations
---@return string[]
function M.list()
  local available = require("buildkite.credentials").list_available()
  local orgs = vim.tbl_keys(available)
  return vim.tbl_filter(function(org)
    return org ~= "_default"
  end, orgs)
end

---Show current configuration info
function M.show_info()
  local current = M.get_current()
  local pipeline = require("buildkite.pipeline").get_slug()
  local orgs = M.list()

  local lines = {
    "Buildkite Configuration",
    "=======================",
    "",
    "Current Organization: " .. (current or "(none)"),
    "Detected Pipeline:    " .. (pipeline or "(none)"),
    "",
    "Configured Organizations:",
  }

  if #orgs == 0 then
    table.insert(lines, "  (none)")
  else
    for _, org in ipairs(orgs) do
      local marker = org == current and " *" or ""
      table.insert(lines, "  - " .. org .. marker)
    end
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

return M
