local M = {}

---Check if buildkite-agent is available
---@return boolean
function M.has_agent()
  return vim.fn.executable("buildkite-agent") == 1
end

---@class BuildkiteStep
---@field label string|nil
---@field command string|string[]|nil
---@field commands string[]|nil
---@field env table<string, string>|nil
---@field plugins table[]|nil
---@field row number 0-indexed line number
---@field col number 0-indexed column

---Parse pipeline YAML and extract steps
---@param bufnr number
---@return BuildkiteStep[]
function M.parse_steps(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local lint = require("buildkite.lint")
  if not lint.has_yaml_parser() then
    return {}
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "yaml")
  if not ok or not parser then
    return {}
  end

  local tree = parser:parse()[1]
  if not tree then
    return {}
  end

  local root = tree:root()
  local steps = {}

  -- Query for step items
  local query_str = [[
    (block_sequence_item) @step
  ]]

  local query_ok, query = pcall(vim.treesitter.query.parse, "yaml", query_str)
  if not query_ok then
    return {}
  end

  for _, node in query:iter_captures(root, bufnr) do
    local step = M._parse_step_node(node, bufnr)
    if step and (step.command or step.commands) then
      table.insert(steps, step)
    end
  end

  return steps
end

---Parse a single step node
---@param node TSNode
---@param bufnr number
---@return BuildkiteStep|nil
function M._parse_step_node(node, bufnr)
  local row, col = node:range()
  local step = { row = row, col = col }

  -- Find the block_mapping inside the sequence item
  local mapping = nil
  for child in node:iter_children() do
    if child:type() == "block_node" then
      for subchild in child:iter_children() do
        if subchild:type() == "block_mapping" then
          mapping = subchild
          break
        end
      end
    elseif child:type() == "block_mapping" then
      mapping = child
    end
  end

  if not mapping then
    return nil
  end

  -- Extract key-value pairs
  for child in mapping:iter_children() do
    if child:type() == "block_mapping_pair" then
      local key_node = nil
      local value_node = nil

      for pair_child in child:iter_children() do
        if pair_child:type() == "flow_node" or pair_child:type() == "block_node" then
          if not key_node then
            key_node = pair_child
          else
            value_node = pair_child
          end
        end
      end

      if key_node then
        local key = vim.treesitter.get_node_text(key_node, bufnr)

        if key == "label" and value_node then
          step.label = vim.treesitter.get_node_text(value_node, bufnr)
        elseif key == "command" and value_node then
          -- command can be a string or an array
          step.command = M._parse_command_value(value_node, bufnr)
        elseif key == "commands" and value_node then
          step.commands = M._parse_string_array(value_node, bufnr)
        elseif key == "env" and value_node then
          step.env = M._parse_env_mapping(value_node, bufnr)
        elseif key == "plugins" then
          step.plugins = {}  -- Mark that plugins exist
        end
      end
    end
  end

  return step
end

---Parse command value (can be string or array)
---@param node TSNode
---@param bufnr number
---@return string|string[]
function M._parse_command_value(node, bufnr)
  -- Check if it's a block sequence (array)
  local sequence = node
  if node:type() == "block_node" then
    for child in node:iter_children() do
      if child:type() == "block_sequence" then
        -- It's an array, parse as such
        return M._parse_string_array(node, bufnr)
      end
    end
  end

  -- It's a scalar string
  return vim.treesitter.get_node_text(node, bufnr)
end

---Parse a YAML array of strings
---@param node TSNode
---@param bufnr number
---@return string[]
function M._parse_string_array(node, bufnr)
  local result = {}

  -- Handle block_node wrapper
  local sequence = node
  if node:type() == "block_node" then
    for child in node:iter_children() do
      if child:type() == "block_sequence" then
        sequence = child
        break
      end
    end
  end

  if sequence:type() ~= "block_sequence" then
    return result
  end

  for child in sequence:iter_children() do
    if child:type() == "block_sequence_item" then
      for item_child in child:iter_children() do
        if item_child:type() ~= "-" then
          local text = vim.treesitter.get_node_text(item_child, bufnr)
          if text then
            table.insert(result, text)
          end
        end
      end
    end
  end

  return result
end

---Parse environment variable mapping
---@param node TSNode
---@param bufnr number
---@return table<string, string>
function M._parse_env_mapping(node, bufnr)
  local result = {}

  local mapping = node
  if node:type() == "block_node" then
    for child in node:iter_children() do
      if child:type() == "block_mapping" then
        mapping = child
        break
      end
    end
  end

  if mapping:type() ~= "block_mapping" then
    return result
  end

  for child in mapping:iter_children() do
    if child:type() == "block_mapping_pair" then
      local key = nil
      local value = nil

      for pair_child in child:iter_children() do
        local text = vim.treesitter.get_node_text(pair_child, bufnr)
        if pair_child:type() == "flow_node" or pair_child:type() == "plain_scalar" then
          if not key then
            key = text
          else
            value = text
          end
        end
      end

      if key and value then
        result[key] = value
      end
    end
  end

  return result
end

---Get commands from a step
---@param step BuildkiteStep
---@return string[]
function M.get_step_commands(step)
  if step.commands then
    return step.commands
  elseif step.command then
    if type(step.command) == "table" then
      return step.command
    else
      return { step.command }
    end
  end
  return {}
end

---Find step at cursor position
---@param bufnr number|nil
---@return BuildkiteStep|nil
function M.get_step_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor[1] - 1  -- Convert to 0-indexed

  local steps = M.parse_steps(bufnr)

  -- Find step that contains cursor
  local best_match = nil
  for _, step in ipairs(steps) do
    if step.row <= cursor_row then
      if not best_match or step.row > best_match.row then
        best_match = step
      end
    end
  end

  return best_match
end

---Run a step locally
---@param step BuildkiteStep
function M.run_step(step)
  local commands = M.get_step_commands(step)
  if #commands == 0 then
    vim.notify("Step has no commands to run", vim.log.levels.WARN)
    return
  end

  -- Warn about plugins
  if step.plugins and next(step.plugins) then
    vim.notify("Step has plugins which will be skipped in local execution", vim.log.levels.WARN)
  end

  -- Build environment exports
  local env_exports = {}
  if step.env then
    for k, v in pairs(step.env) do
      table.insert(env_exports, string.format("export %s=%s", k, vim.fn.shellescape(v)))
    end
  end

  -- Build the full command
  local cmd_parts = {}
  if #env_exports > 0 then
    table.insert(cmd_parts, table.concat(env_exports, " && "))
  end
  table.insert(cmd_parts, table.concat(commands, " && "))

  local cmd = table.concat(cmd_parts, " && ")
  local label = step.label or "step"

  -- Open terminal buffer
  vim.cmd("botright split")
  vim.cmd("resize 15")
  local term_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, term_buf)
  vim.api.nvim_buf_set_name(term_buf, "Buildkite: " .. label)

  -- Run in terminal
  vim.fn.termopen(cmd, {
    cwd = vim.fn.getcwd(),
    on_exit = function(_, code)
      if code == 0 then
        vim.notify(string.format("Step '%s' completed successfully", label), vim.log.levels.INFO)
      else
        vim.notify(string.format("Step '%s' failed with exit code %d", label, code), vim.log.levels.ERROR)
      end
    end,
  })

  vim.cmd("startinsert")
end

---Run the step under cursor
function M.run_step_at_cursor()
  local pipeline = require("buildkite.pipeline")

  if not pipeline.is_pipeline_file() then
    vim.notify("Not in a Buildkite pipeline file", vim.log.levels.ERROR)
    return
  end

  local step = M.get_step_at_cursor()
  if not step then
    vim.notify("No step found at cursor position", vim.log.levels.WARN)
    return
  end

  M.run_step(step)
end

---Select a step and run it
function M.run_step_select()
  local pipeline = require("buildkite.pipeline")

  if not pipeline.is_pipeline_file() then
    -- Try to find pipeline file
    local file = pipeline.find_pipeline_file()
    if file then
      vim.cmd("edit " .. file)
    else
      vim.notify("No Buildkite pipeline file found", vim.log.levels.ERROR)
      return
    end
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local steps = M.parse_steps(bufnr)

  if #steps == 0 then
    vim.notify("No runnable steps found in pipeline", vim.log.levels.WARN)
    return
  end

  local items = {}
  for i, step in ipairs(steps) do
    local label = step.label or ("Step " .. i)
    local cmds = M.get_step_commands(step)
    local preview = #cmds > 0 and cmds[1]:sub(1, 40) or ""
    table.insert(items, {
      label = label,
      preview = preview,
      step = step,
    })
  end

  vim.ui.select(items, {
    prompt = "Select step to run:",
    format_item = function(item)
      if item.preview ~= "" then
        return item.label .. " (" .. item.preview .. "...)"
      end
      return item.label
    end,
  }, function(choice)
    if choice then
      M.run_step(choice.step)
    end
  end)
end

return M
