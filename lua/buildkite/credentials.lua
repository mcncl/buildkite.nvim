local M = {}

---@class BuildkiteCredential
---@field token string The API token
---@field source string Where the token was loaded from

---@param org_slug string|nil Organization slug for org-specific env var
---@return BuildkiteCredential|nil
local function get_from_env(org_slug)
  -- Try org-specific env var first
  if org_slug then
    local org_upper = string.upper(org_slug:gsub("-", "_"))
    local org_token = vim.env["BUILDKITE_TOKEN_" .. org_upper]
    if org_token and org_token ~= "" then
      return { token = org_token, source = "env:BUILDKITE_TOKEN_" .. org_upper }
    end
  end

  -- Fall back to generic env var
  local token = vim.env.BUILDKITE_API_TOKEN
  if token and token ~= "" then
    return { token = token, source = "env:BUILDKITE_API_TOKEN" }
  end

  return nil
end

---@param org_slug string Organization slug
---@return BuildkiteCredential|nil
local function get_from_keychain(org_slug)
  -- Only supported on macOS
  if vim.fn.has("mac") ~= 1 then
    return nil
  end

  local service = "buildkite-nvim"
  local account = org_slug

  -- Use security CLI to get from keychain
  local result = vim.fn.system({
    "security",
    "find-generic-password",
    "-s", service,
    "-a", account,
    "-w",
  })

  -- Check if command succeeded (exit code 0 and non-empty output)
  if vim.v.shell_error == 0 and result and result ~= "" then
    local token = vim.trim(result)
    if token ~= "" then
      return { token = token, source = "keychain:" .. org_slug }
    end
  end

  return nil
end

---@param org_slug string Organization slug
---@return BuildkiteCredential|nil
local function get_from_config(org_slug)
  local config = require("buildkite.config").get()
  local config_path = config.config_path

  if vim.fn.filereadable(config_path) ~= 1 then
    return nil
  end

  local ok, content = pcall(vim.fn.readfile, config_path)
  if not ok then
    return nil
  end

  local json_ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
  if not json_ok or not data then
    return nil
  end

  local orgs = data.organizations or {}
  local org_data = orgs[org_slug]

  if org_data and org_data.token and org_data.token ~= "" then
    return { token = org_data.token, source = "config:" .. config_path }
  end

  return nil
end

---Get API token for an organization using precedence: env > keychain > config
---@param org_slug string Organization slug
---@return BuildkiteCredential|nil credential
---@return string|nil error
function M.get_token(org_slug)
  if not org_slug or org_slug == "" then
    return nil, "Organization slug is required"
  end

  -- 1. Environment variables (highest priority)
  local env_cred = get_from_env(org_slug)
  if env_cred then
    return env_cred, nil
  end

  -- 2. System keychain
  local keychain_cred = get_from_keychain(org_slug)
  if keychain_cred then
    return keychain_cred, nil
  end

  -- 3. Config file (lowest priority)
  local config_cred = get_from_config(org_slug)
  if config_cred then
    return config_cred, nil
  end

  return nil, string.format("No token found for organization '%s'", org_slug)
end

---Store token in keychain (macOS only)
---@param org_slug string Organization slug
---@param token string API token
---@return boolean success
---@return string|nil error
function M.store_in_keychain(org_slug, token)
  if vim.fn.has("mac") ~= 1 then
    return false, "Keychain storage is only supported on macOS"
  end

  local service = "buildkite-nvim"

  -- Delete existing entry first (ignore errors)
  vim.fn.system({
    "security",
    "delete-generic-password",
    "-s", service,
    "-a", org_slug,
  })

  -- Add new entry
  local result = vim.fn.system({
    "security",
    "add-generic-password",
    "-s", service,
    "-a", org_slug,
    "-w", token,
  })

  if vim.v.shell_error ~= 0 then
    return false, "Failed to store in keychain: " .. vim.trim(result)
  end

  return true, nil
end

---Store token in config file
---@param org_slug string Organization slug
---@param token string API token
---@param extra_data table|nil Additional data to store (e.g., default_pipeline)
---@return boolean success
---@return string|nil error
function M.store_in_config(org_slug, token, extra_data)
  local config = require("buildkite.config").get()
  local config_path = config.config_path

  -- Read existing config or start fresh
  local data = { organizations = {} }
  if vim.fn.filereadable(config_path) == 1 then
    local ok, content = pcall(vim.fn.readfile, config_path)
    if ok then
      local json_ok, parsed = pcall(vim.json.decode, table.concat(content, "\n"))
      if json_ok and parsed then
        data = parsed
        data.organizations = data.organizations or {}
      end
    end
  end

  -- Update org data
  data.organizations[org_slug] = vim.tbl_extend("force", data.organizations[org_slug] or {}, {
    token = token,
  }, extra_data or {})

  -- Set as current org if first one
  if not data.current_org then
    data.current_org = org_slug
  end

  -- Ensure parent directory exists
  local parent_dir = vim.fn.fnamemodify(config_path, ":h")
  if vim.fn.isdirectory(parent_dir) ~= 1 then
    vim.fn.mkdir(parent_dir, "p")
  end

  -- Write config
  local json_str = vim.json.encode(data)
  local ok, err = pcall(vim.fn.writefile, { json_str }, config_path)
  if not ok then
    return false, "Failed to write config: " .. tostring(err)
  end

  return true, nil
end

---Check if any credentials are available
---@return table<string, string> Map of org_slug -> source for available creds
function M.list_available()
  local available = {}
  local config = require("buildkite.config").get()

  -- Check generic env var
  if vim.env.BUILDKITE_API_TOKEN and vim.env.BUILDKITE_API_TOKEN ~= "" then
    available["_default"] = "env:BUILDKITE_API_TOKEN"
  end

  -- Check config file
  local config_path = config.config_path
  if vim.fn.filereadable(config_path) == 1 then
    local ok, content = pcall(vim.fn.readfile, config_path)
    if ok then
      local json_ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
      if json_ok and data and data.organizations then
        for org_slug, org_data in pairs(data.organizations) do
          if org_data.token and org_data.token ~= "" then
            available[org_slug] = "config"
          end
        end
      end
    end
  end

  return available
end

return M
