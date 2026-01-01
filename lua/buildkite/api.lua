local M = {}

local BASE_URL = "https://api.buildkite.com/v2"

---@class BuildkiteApiError
---@field status number HTTP status code
---@field message string Error message
---@field body string|nil Response body

---Run curl command asynchronously
---@param args string[] curl arguments
---@param callback function Callback(err, response)
local function curl_request(args, callback)
  local Job = require("plenary.job")

  local stdout_data = {}
  local stderr_data = {}

  Job:new({
    command = "curl",
    args = args,
    on_stdout = function(_, data)
      table.insert(stdout_data, data)
    end,
    on_stderr = function(_, data)
      table.insert(stderr_data, data)
    end,
    on_exit = function(_, return_val)
      vim.schedule(function()
        local body = table.concat(stdout_data, "\n")

        -- Parse the status code from the last line (we use -w to append it)
        local status_code = tonumber(body:match("HTTP_STATUS:(%d+)$"))
        body = body:gsub("HTTP_STATUS:%d+$", "")

        if return_val ~= 0 then
          callback({ status = 0, message = "curl failed: " .. table.concat(stderr_data, "\n") }, nil)
          return
        end

        callback(nil, { status = status_code or 0, body = body })
      end)
    end,
  }):start()
end

---@param method string HTTP method
---@param path string API path (without base URL)
---@param opts table|nil Options: body, org_slug, token
---@param callback function Callback(err, response)
local function request(method, path, opts, callback)
  opts = opts or {}

  local token = opts.token
  if not token then
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
    token = cred.token
  end

  local url = BASE_URL .. path

  local args = {
    "-s",
    "-X", method,
    "-H", "Authorization: Bearer " .. token,
    "-H", "Content-Type: application/json",
    "-w", "HTTP_STATUS:%{http_code}",
  }

  if opts.body then
    table.insert(args, "-d")
    table.insert(args, vim.json.encode(opts.body))
  end

  table.insert(args, url)

  curl_request(args, function(err, response)
    if err then
      callback(err, nil)
      return
    end

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

---Handle 404 error by prompting user for correct pipeline slug
---@param detected_slug string The slug that was tried
---@param retry_fn function Function to retry after setting correct slug
local function handle_pipeline_404(detected_slug, retry_fn)
  vim.notify("Pipeline '" .. detected_slug .. "' not found.", vim.log.levels.WARN)

  vim.ui.select({ "Enter correct slug", "List available pipelines", "Cancel" }, {
    prompt = "Pipeline not found. What would you like to do?",
  }, function(choice)
    if choice == "Enter correct slug" then
      vim.ui.input({
        prompt = "Enter pipeline slug: ",
        default = detected_slug,
      }, function(slug)
        if slug and slug ~= "" then
          local pipeline = require("buildkite.pipeline")
          pipeline.set_override(slug)
          -- Cache for future use
          local remote = pipeline.get_git_remote()
          if remote then
            pipeline.cache_slug(remote, slug)
          end
          -- Retry the operation
          if retry_fn then
            retry_fn()
          end
        end
      end)
    elseif choice == "List available pipelines" then
      M.list_pipelines(function(err, pipelines)
        if err then
          vim.notify("Failed to list pipelines: " .. (err.message or "unknown error"), vim.log.levels.ERROR)
          return
        end
        if not pipelines or #pipelines == 0 then
          vim.notify("No pipelines found in this organization", vim.log.levels.WARN)
          return
        end
        require("buildkite.ui.picker").show_pipelines(pipelines, function(slug)
          local pipeline = require("buildkite.pipeline")
          pipeline.set_override(slug)
          local remote = pipeline.get_git_remote()
          if remote then
            pipeline.cache_slug(remote, slug)
          end
          if retry_fn then
            retry_fn()
          end
        end)
      end)
    end
  end)
end

---List builds for a pipeline
---@param callback function|nil Callback(err, builds) - if nil, opens picker
function M.list_builds(callback)
  local org_slug = require("buildkite.organizations").get_current()
  local pipeline_slug = require("buildkite.pipeline").get_slug()

  if not org_slug then
    vim.notify("No organization configured. Run :Buildkite org add first.", vim.log.levels.ERROR)
    return
  end

  if not pipeline_slug then
    vim.notify("Could not detect pipeline. Run :Buildkite pipeline set <slug>", vim.log.levels.ERROR)
    return
  end

  local path = "/organizations/" .. org_slug .. "/pipelines/" .. pipeline_slug .. "/builds?per_page=20"

  request("GET", path, {}, function(err, response)
    if err then
      if err.status == 404 then
        handle_pipeline_404(pipeline_slug, function()
          M.list_builds(callback)
        end)
      else
        vim.notify("Failed to fetch builds: " .. err.message, vim.log.levels.ERROR)
        if callback then callback(err, nil) end
      end
      return
    end

    if callback then
      callback(nil, response.body)
    else
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
    vim.notify("No organization configured. Run :Buildkite org add first.", vim.log.levels.ERROR)
    return
  end

  if not pipeline_slug then
    vim.notify("Could not detect pipeline. Run :Buildkite pipeline set <slug>", vim.log.levels.ERROR)
    return
  end

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
      if err.status == 404 then
        handle_pipeline_404(pipeline_slug, function()
          M.trigger_build(branch)
        end)
      else
        vim.notify("Failed to trigger build: " .. err.message, vim.log.levels.ERROR)
      end
      return
    end

    local build = response.body
    vim.notify(string.format("Build #%d triggered on branch '%s'", build.number, branch), vim.log.levels.INFO)

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
  request("GET", "/organizations/" .. org_slug, { token = token }, function(err, response)
    if err then
      if err.status == 401 then
        callback(false, "Invalid token")
      elseif err.status == 404 then
        callback(false, "Organization not found or no access")
      else
        callback(false, err.message or "Unknown error")
      end
      return
    end

    callback(true, "Token is valid")
  end)
end

return M
