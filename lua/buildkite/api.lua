local M = {}

local BASE_URL = "https://api.buildkite.com/v2"

---@class BuildkiteApiError
---@field status number HTTP status code
---@field message string Error message
---@field body string|nil Response body

---@param method string HTTP method
---@param path string API path (without base URL)
---@param opts table|nil Options: body, org_slug
---@param callback function Callback(err, response)
local function request(method, path, opts, callback)
  opts = opts or {}
  local org_slug = opts.org_slug or require("buildkite.organizations").get_current()

  if not org_slug then
    callback({ status = 0, message = "No organization configured" }, nil)
    return
  end

  local credentials = require("buildkite.credentials")
  local cred, cred_err = credentials.get_token(org_slug)
  if not cred then
    callback({ status = 0, message = cred_err or "No credentials found" }, nil)
    return
  end

  local curl = require("plenary.curl")
  local url = BASE_URL .. path

  local request_opts = {
    url = url,
    method = method,
    headers = {
      ["Authorization"] = "Bearer " .. cred.token,
      ["Content-Type"] = "application/json",
    },
    callback = function(response)
      vim.schedule(function()
        if response.status >= 200 and response.status < 300 then
          local body = nil
          if response.body and response.body ~= "" then
            local ok, decoded = pcall(vim.json.decode, response.body)
            body = ok and decoded or response.body
          end
          callback(nil, { status = response.status, body = body })
        else
          local err_msg = "Request failed"
          if response.body and response.body ~= "" then
            local ok, decoded = pcall(vim.json.decode, response.body)
            if ok and decoded and decoded.message then
              err_msg = decoded.message
            end
          end
          callback({
            status = response.status,
            message = err_msg,
            body = response.body,
          }, nil)
        end
      end)
    end,
  }

  if opts.body then
    request_opts.body = vim.json.encode(opts.body)
  end

  curl.request(request_opts)
end

---List pipelines for the current organization
---@param callback function Callback(err, pipelines)
function M.list_pipelines(callback)
  local org_slug = require("buildkite.organizations").get_current()
  if not org_slug then
    callback({ message = "No organization configured" }, nil)
    return
  end

  request("GET", "/organizations/" .. org_slug .. "/pipelines", {}, function(err, response)
    if err then
      callback(err, nil)
    else
      callback(nil, response.body)
    end
  end)
end

---Get pipeline details
---@param pipeline_slug string Pipeline slug
---@param callback function Callback(err, pipeline)
function M.get_pipeline(pipeline_slug, callback)
  local org_slug = require("buildkite.organizations").get_current()
  if not org_slug then
    callback({ message = "No organization configured" }, nil)
    return
  end

  request("GET", "/organizations/" .. org_slug .. "/pipelines/" .. pipeline_slug, {}, function(err, response)
    if err then
      callback(err, nil)
    else
      callback(nil, response.body)
    end
  end)
end

---List builds for a pipeline
---@param callback function|nil Callback(err, builds) - if nil, opens picker
function M.list_builds(callback)
  local org_slug = require("buildkite.organizations").get_current()
  local pipeline_slug = require("buildkite.pipeline").get_slug()

  if not org_slug then
    vim.notify("No organization configured. Run :BuildkiteAddOrg first.", vim.log.levels.ERROR)
    return
  end

  if not pipeline_slug then
    vim.notify("Could not detect pipeline. Run :BuildkiteSetPipeline <slug>", vim.log.levels.ERROR)
    return
  end

  local path = "/organizations/" .. org_slug .. "/pipelines/" .. pipeline_slug .. "/builds"

  request("GET", path .. "?per_page=20", {}, function(err, response)
    if err then
      if err.status == 404 then
        vim.notify("Pipeline '" .. pipeline_slug .. "' not found. Use :BuildkiteSetPipeline to set correct slug.", vim.log.levels.WARN)
      else
        vim.notify("Failed to fetch builds: " .. err.message, vim.log.levels.ERROR)
      end
      if callback then callback(err, nil) end
      return
    end

    if callback then
      callback(nil, response.body)
    else
      -- Show builds in picker
      require("buildkite.ui.picker").show_builds(response.body)
    end
  end)
end

---Trigger a new build
---@param branch string|nil Branch to build (defaults to current git branch)
function M.trigger_build(branch)
  local org_slug = require("buildkite.organizations").get_current()
  local pipeline_slug = require("buildkite.pipeline").get_slug()

  if not org_slug then
    vim.notify("No organization configured. Run :BuildkiteAddOrg first.", vim.log.levels.ERROR)
    return
  end

  if not pipeline_slug then
    vim.notify("Could not detect pipeline. Run :BuildkiteSetPipeline <slug>", vim.log.levels.ERROR)
    return
  end

  -- Get current branch if not specified
  if not branch then
    local git = require("buildkite.pipeline")
    branch = git.get_current_branch() or "main"
  end

  local path = "/organizations/" .. org_slug .. "/pipelines/" .. pipeline_slug .. "/builds"

  request("POST", path, {
    body = {
      commit = "HEAD",
      branch = branch,
      message = "Build triggered from Neovim",
    },
  }, function(err, response)
    if err then
      vim.notify("Failed to trigger build: " .. err.message, vim.log.levels.ERROR)
      return
    end

    local build = response.body
    vim.notify(string.format("Build #%d triggered on branch '%s'", build.number, branch), vim.log.levels.INFO)

    -- Optionally open build URL
    if build.web_url then
      vim.ui.select({ "Open in browser", "Copy URL", "Dismiss" }, {
        prompt = "Build triggered:",
      }, function(choice)
        if choice == "Open in browser" then
          vim.ui.open(build.web_url)
        elseif choice == "Copy URL" then
          vim.fn.setreg("+", build.web_url)
          vim.notify("URL copied to clipboard", vim.log.levels.INFO)
        end
      end)
    end
  end)
end

---Validate API token
---@param org_slug string Organization slug
---@param token string API token
---@param callback function Callback(valid, message)
function M.validate_token(org_slug, token, callback)
  local curl = require("plenary.curl")

  curl.get(BASE_URL .. "/organizations/" .. org_slug, {
    headers = {
      ["Authorization"] = "Bearer " .. token,
    },
    callback = function(response)
      vim.schedule(function()
        if response.status == 200 then
          callback(true, "Token is valid")
        elseif response.status == 401 then
          callback(false, "Invalid token")
        elseif response.status == 404 then
          callback(false, "Organization not found or no access")
        else
          callback(false, "Unexpected error: " .. response.status)
        end
      end)
    end,
  })
end

return M
