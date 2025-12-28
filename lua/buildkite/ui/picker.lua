local M = {}

---Check if telescope is available
---@return boolean
function M.has_telescope()
  local ok = pcall(require, "telescope")
  return ok
end

---Format build state for display
---@param state string
---@return string
local function format_state(state)
  local icons = {
    passed = "✓",
    failed = "✗",
    canceled = "⊘",
    running = "●",
    scheduled = "○",
    blocked = "■",
    canceling = "…",
    skipped = "○",
    not_run = "○",
  }
  return icons[state] or "?"
end

---Format relative time
---@param timestamp string ISO timestamp
---@return string
local function format_time(timestamp)
  if not timestamp then
    return ""
  end

  -- Parse ISO timestamp (simplified)
  local year, month, day, hour, min, sec = timestamp:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not year then
    return ""
  end

  local build_time = os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
  })

  local diff = os.time() - build_time

  if diff < 60 then
    return "just now"
  elseif diff < 3600 then
    return math.floor(diff / 60) .. "m ago"
  elseif diff < 86400 then
    return math.floor(diff / 3600) .. "h ago"
  else
    return math.floor(diff / 86400) .. "d ago"
  end
end

---Show builds using telescope or vim.ui.select
---@param builds table[] List of build objects from API
function M.show_builds(builds)
  if not builds or #builds == 0 then
    vim.notify("No builds found", vim.log.levels.INFO)
    return
  end

  if M.has_telescope() then
    M._show_builds_telescope(builds)
  else
    M._show_builds_select(builds)
  end
end

---Show builds using telescope
---@param builds table[]
function M._show_builds_telescope(builds)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = "Buildkite Builds",
    finder = finders.new_table({
      results = builds,
      entry_maker = function(build)
        local state_icon = format_state(build.state)
        local time = format_time(build.created_at)
        local branch = build.branch or ""
        local message = build.message or ""

        -- Truncate message
        if #message > 50 then
          message = message:sub(1, 47) .. "..."
        end

        local display = string.format(
          "%s #%d %s - %s (%s)",
          state_icon,
          build.number,
          branch,
          message,
          time
        )

        return {
          value = build,
          display = display,
          ordinal = string.format("%d %s %s", build.number, branch, message),
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection and selection.value.web_url then
          vim.ui.open(selection.value.web_url)
        end
      end)

      map("i", "<C-y>", function()
        local selection = action_state.get_selected_entry()
        if selection and selection.value.web_url then
          vim.fn.setreg("+", selection.value.web_url)
          vim.notify("URL copied to clipboard", vim.log.levels.INFO)
        end
      end)

      return true
    end,
  }):find()
end

---Show builds using vim.ui.select
---@param builds table[]
function M._show_builds_select(builds)
  local items = {}
  for _, build in ipairs(builds) do
    local state_icon = format_state(build.state)
    local time = format_time(build.created_at)
    local branch = build.branch or ""
    local message = build.message or ""

    if #message > 40 then
      message = message:sub(1, 37) .. "..."
    end

    table.insert(items, {
      display = string.format("%s #%d %s - %s (%s)", state_icon, build.number, branch, message, time),
      build = build,
    })
  end

  vim.ui.select(items, {
    prompt = "Select build:",
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if choice and choice.build.web_url then
      vim.ui.select({ "Open in browser", "Copy URL", "Dismiss" }, {
        prompt = "Build #" .. choice.build.number,
      }, function(action)
        if action == "Open in browser" then
          vim.ui.open(choice.build.web_url)
        elseif action == "Copy URL" then
          vim.fn.setreg("+", choice.build.web_url)
          vim.notify("URL copied to clipboard", vim.log.levels.INFO)
        end
      end)
    end
  end)
end

---Show pipelines picker
---@param pipelines table[]
---@param callback function|nil Callback when pipeline is selected
function M.show_pipelines(pipelines, callback)
  if not pipelines or #pipelines == 0 then
    vim.notify("No pipelines found", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, pipeline in ipairs(pipelines) do
    table.insert(items, {
      slug = pipeline.slug,
      name = pipeline.name or pipeline.slug,
      description = pipeline.description,
    })
  end

  vim.ui.select(items, {
    prompt = "Select pipeline:",
    format_item = function(item)
      if item.description and item.description ~= "" then
        return item.name .. " - " .. item.description
      end
      return item.name
    end,
  }, function(choice)
    if choice and callback then
      callback(choice.slug)
    end
  end)
end

return M
