local M = {}

-- Command tree: noun -> verb -> handler
local commands = {
  org = {
    add = {
      handler = function(args)
        if not args[1] then
          vim.notify("Usage: :Buildkite org add <slug>", vim.log.levels.ERROR)
          return
        end
        require("buildkite.organizations").add(args[1])
      end,
      desc = "Add a Buildkite organization",
      nargs = 1,
    },
    switch = {
      handler = function()
        require("buildkite.organizations").switch()
      end,
      desc = "Switch to a different organization",
    },
    list = {
      handler = function()
        local orgs = require("buildkite.organizations").list()
        if #orgs == 0 then
          vim.notify("No organizations configured", vim.log.levels.INFO)
        else
          vim.notify("Organizations:\n  " .. table.concat(orgs, "\n  "), vim.log.levels.INFO)
        end
      end,
      desc = "List configured organizations",
    },
    info = {
      handler = function()
        require("buildkite.organizations").show_info()
      end,
      desc = "Show current organization info",
    },
  },
  pipeline = {
    set = {
      handler = function(args)
        if not args[1] then
          vim.notify("Usage: :Buildkite pipeline set <slug>", vim.log.levels.ERROR)
          return
        end
        require("buildkite.pipeline").set_override(args[1])
      end,
      desc = "Override the detected pipeline slug",
      nargs = 1,
    },
    lint = {
      handler = function()
        require("buildkite.lint").lint_buffer()
      end,
      desc = "Lint the current pipeline file",
    },
    info = {
      handler = function()
        local slug = require("buildkite.pipeline").get_slug()
        local file = require("buildkite.pipeline").find_pipeline_file()
        local lines = { "Pipeline Info:" }
        table.insert(lines, "  Slug: " .. (slug or "(not detected)"))
        table.insert(lines, "  File: " .. (file or "(not found)"))
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
      end,
      desc = "Show detected pipeline info",
    },
  },
  build = {
    list = {
      handler = function()
        require("buildkite.api").list_builds()
      end,
      desc = "List recent builds",
    },
    trigger = {
      handler = function(args)
        local branch = args[1]
        require("buildkite.api").trigger_build(branch)
      end,
      desc = "Trigger a new build",
      nargs = "?",
    },
  },
  step = {
    run = {
      handler = function()
        require("buildkite.runner").run_step_at_cursor()
      end,
      desc = "Run the step under cursor locally",
    },
    select = {
      handler = function()
        require("buildkite.runner").run_step_select()
      end,
      desc = "Select and run a step locally",
    },
  },
}

-- Build completion list
local function get_completions(arg_lead, cmd_line)
  local parts = vim.split(vim.trim(cmd_line), "%s+")
  -- parts[1] = "Buildkite", parts[2] = noun, parts[3] = verb, etc.

  local results = {}

  if #parts == 1 or (#parts == 2 and arg_lead ~= "") then
    -- Complete noun
    for noun in pairs(commands) do
      if noun:find("^" .. arg_lead) then
        table.insert(results, noun)
      end
    end
  elseif #parts == 2 or (#parts == 3 and arg_lead ~= "") then
    -- Complete verb
    local noun = parts[2]
    if commands[noun] then
      for verb in pairs(commands[noun]) do
        if verb:find("^" .. arg_lead) then
          table.insert(results, verb)
        end
      end
    end
  end

  table.sort(results)
  return results
end

-- Parse and execute command
local function execute(args)
  local parts = args.fargs

  if #parts == 0 then
    M.show_help()
    return
  end

  local noun = parts[1]
  local verb = parts[2]
  local rest = vim.list_slice(parts, 3)

  if not commands[noun] then
    vim.notify("Unknown command: " .. noun .. "\nRun :Buildkite for help", vim.log.levels.ERROR)
    return
  end

  if not verb then
    -- Show available verbs for this noun
    local verbs = vim.tbl_keys(commands[noun])
    table.sort(verbs)
    vim.notify("Usage: :Buildkite " .. noun .. " <" .. table.concat(verbs, "|") .. ">", vim.log.levels.INFO)
    return
  end

  if not commands[noun][verb] then
    vim.notify("Unknown command: " .. noun .. " " .. verb, vim.log.levels.ERROR)
    return
  end

  commands[noun][verb].handler(rest)
end

function M.show_help()
  local lines = { "Buildkite.nvim Commands:", "" }

  local nouns = vim.tbl_keys(commands)
  table.sort(nouns)

  for _, noun in ipairs(nouns) do
    table.insert(lines, "  " .. noun .. ":")
    local verbs = vim.tbl_keys(commands[noun])
    table.sort(verbs)
    for _, verb in ipairs(verbs) do
      local cmd = commands[noun][verb]
      local usage = ":Buildkite " .. noun .. " " .. verb
      if cmd.nargs == 1 then
        usage = usage .. " <arg>"
      elseif cmd.nargs == "?" then
        usage = usage .. " [arg]"
      end
      table.insert(lines, string.format("    %-35s %s", usage, cmd.desc))
    end
    table.insert(lines, "")
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.setup()
  vim.api.nvim_create_user_command("Buildkite", execute, {
    nargs = "*",
    complete = get_completions,
    desc = "Buildkite plugin commands",
  })
end

return M
