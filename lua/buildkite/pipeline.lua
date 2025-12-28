local M = {}

-- Buffer-local override
local pipeline_override = nil

-- Cache of git remote -> pipeline slug mappings
local slug_cache = {}

---Set a manual pipeline slug override
---@param slug string
function M.set_override(slug)
  pipeline_override = slug
  vim.notify("Pipeline set to: " .. slug, vim.log.levels.INFO)
end

---Clear the pipeline override
function M.clear_override()
  pipeline_override = nil
  vim.notify("Pipeline override cleared", vim.log.levels.INFO)
end

---Get the current git branch
---@return string|nil
function M.get_current_branch()
  local result = vim.fn.system("git rev-parse --abbrev-ref HEAD 2>/dev/null")
  if vim.v.shell_error == 0 and result then
    return vim.trim(result)
  end
  return nil
end

---Get the git remote URL
---@return string|nil
function M.get_git_remote()
  local result = vim.fn.system("git remote get-url origin 2>/dev/null")
  if vim.v.shell_error == 0 and result then
    return vim.trim(result)
  end
  return nil
end

---Extract repo name from git remote URL
---@param remote_url string
---@return string|nil
local function extract_repo_name(remote_url)
  -- Handle SSH format: git@github.com:user/repo.git
  local ssh_match = remote_url:match("^git@[^:]+:(.+)$")
  if ssh_match then
    -- Remove .git suffix and get repo name (last path component)
    local path = ssh_match:gsub("%.git$", "")
    return path:match("([^/]+)$")
  end

  -- Handle HTTPS format: https://github.com/user/repo.git
  local https_match = remote_url:match("^https?://[^/]+/(.+)$")
  if https_match then
    local path = https_match:gsub("%.git$", "")
    return path:match("([^/]+)$")
  end

  return nil
end

---Check for project-local .buildkite.lua config
---@return string|nil
local function get_from_local_config()
  local cwd = vim.fn.getcwd()
  local config_path = cwd .. "/.buildkite.lua"

  if vim.fn.filereadable(config_path) == 1 then
    local ok, config = pcall(dofile, config_path)
    if ok and config and config.pipeline then
      return config.pipeline
    end
  end

  return nil
end

---Get pipeline slug using detection chain
---@return string|nil
function M.get_slug()
  -- 1. Manual override (highest priority)
  if pipeline_override then
    return pipeline_override
  end

  -- 2. Project-local .buildkite.lua
  local local_config = get_from_local_config()
  if local_config then
    return local_config
  end

  -- 3. Git remote (extract repo name)
  local remote = M.get_git_remote()
  if remote then
    -- Check cache first
    if slug_cache[remote] then
      return slug_cache[remote]
    end

    local repo_name = extract_repo_name(remote)
    if repo_name then
      return repo_name
    end
  end

  -- 4. Current directory basename (lowest priority)
  local cwd = vim.fn.getcwd()
  local basename = vim.fn.fnamemodify(cwd, ":t")
  if basename and basename ~= "" then
    return basename
  end

  return nil
end

---Cache a pipeline slug for a git remote (after successful API call)
---@param remote string Git remote URL
---@param slug string Verified pipeline slug
function M.cache_slug(remote, slug)
  slug_cache[remote] = slug
end

---Find buildkite pipeline file in current project
---@return string|nil
function M.find_pipeline_file()
  local candidates = {
    ".buildkite/pipeline.yml",
    ".buildkite/pipeline.yaml",
    "buildkite.yml",
    "buildkite.yaml",
    ".buildkite.yml",
    ".buildkite.yaml",
  }

  local cwd = vim.fn.getcwd()
  for _, candidate in ipairs(candidates) do
    local path = cwd .. "/" .. candidate
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  return nil
end

---Check if current buffer is a Buildkite pipeline file
---@param bufnr number|nil Buffer number (defaults to current)
---@return boolean
function M.is_pipeline_file(bufnr)
  bufnr = bufnr or 0
  local filename = vim.api.nvim_buf_get_name(bufnr)

  if filename == "" then
    return false
  end

  -- Check common pipeline file patterns
  local patterns = {
    "%.buildkite/pipeline%.ya?ml$",
    "buildkite%.ya?ml$",
    "%.buildkite%.ya?ml$",
  }

  for _, pattern in ipairs(patterns) do
    if filename:match(pattern) then
      return true
    end
  end

  return false
end

return M
