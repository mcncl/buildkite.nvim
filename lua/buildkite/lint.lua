local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("buildkite_lint")

-- Valid step types
local VALID_STEP_TYPES = {
  command = true,
  commands = true,
  block = true,
  wait = true,
  waiter = true,
  trigger = true,
  input = true,
  group = true,
}

-- Required fields for specific step types
local STEP_REQUIREMENTS = {
  trigger = { "trigger" },
  block = { "block" },
  input = { "input" },
  group = { "group", "steps" },
}

---@class LintDiagnostic
---@field row number 0-indexed line number
---@field col number 0-indexed column
---@field end_row number|nil
---@field end_col number|nil
---@field message string
---@field severity number vim.diagnostic.severity

---Check if treesitter YAML parser is available
---@return boolean
function M.has_yaml_parser()
  local ok, parsers = pcall(require, "nvim-treesitter.parsers")
  if ok and parsers then
    return parsers.has_parser("yaml")
  end

  -- Fallback check for built-in treesitter
  local lang_ok = pcall(vim.treesitter.language.inspect, "yaml")
  return lang_ok
end

---Get the value of a YAML node as string
---@param node TSNode
---@param bufnr number
---@return string|nil
local function get_node_text(node, bufnr)
  if not node then
    return nil
  end
  local text = vim.treesitter.get_node_text(node, bufnr)
  return text
end

---Find a child node by field name or type
---@param node TSNode
---@param field_or_type string
---@return TSNode|nil
local function find_child(node, field_or_type)
  -- Try as field first
  local field_child = node:field(field_or_type)
  if field_child and #field_child > 0 then
    return field_child[1]
  end

  -- Try as type
  for child in node:iter_children() do
    if child:type() == field_or_type then
      return child
    end
  end

  return nil
end

---Extract key-value pairs from a block_mapping node
---@param node TSNode
---@param bufnr number
---@return table<string, TSNode>
local function extract_mapping(node, bufnr)
  local result = {}

  for child in node:iter_children() do
    if child:type() == "block_mapping_pair" then
      local key_node = find_child(child, "key")
      if key_node then
        local key = get_node_text(key_node, bufnr)
        if key then
          local value_node = find_child(child, "value")
          result[key] = value_node or child
        end
      end
    end
  end

  return result
end

---Validate a single step
---@param step_node TSNode
---@param bufnr number
---@return LintDiagnostic[]
local function validate_step(step_node, bufnr)
  local diagnostics = {}
  local row, col = step_node:range()

  -- Handle simple string steps (like "wait")
  if step_node:type() == "flow_node" or step_node:type() == "plain_scalar" then
    local text = get_node_text(step_node, bufnr)
    if text and (text == "wait" or text == "waiter" or text:match("^wait")) then
      return {}  -- Valid wait step
    end
  end

  -- For block mapping steps, extract fields
  if step_node:type() ~= "block_mapping" and step_node:type() ~= "block_node" then
    -- Check if it's a valid simple step type
    local text = get_node_text(step_node, bufnr)
    if text and VALID_STEP_TYPES[text] then
      return {}
    end
    return diagnostics
  end

  local mapping_node = step_node
  if step_node:type() == "block_node" then
    mapping_node = find_child(step_node, "block_mapping")
  end

  if not mapping_node then
    return diagnostics
  end

  local fields = extract_mapping(mapping_node, bufnr)

  -- Determine step type
  local step_type = nil
  for key in pairs(fields) do
    if key == "command" or key == "commands" then
      step_type = "command"
      break
    elseif VALID_STEP_TYPES[key] then
      step_type = key
      break
    end
  end

  if not step_type then
    -- Check for label-only step (probably a command step)
    if fields["label"] and not fields["block"] and not fields["trigger"] then
      table.insert(diagnostics, {
        row = row,
        col = col,
        message = "Step has label but no command, block, trigger, or other step type",
        severity = vim.diagnostic.severity.WARN,
      })
    end
  end

  -- Validate retry configuration
  if fields["retry"] then
    local retry_node = fields["retry"]
    if retry_node:type() == "block_node" then
      local retry_mapping = find_child(retry_node, "block_mapping")
      if retry_mapping then
        local retry_fields = extract_mapping(retry_mapping, bufnr)
        if retry_fields["automatic"] then
          local auto_node = retry_fields["automatic"]
          local auto_text = get_node_text(auto_node, bufnr)
          if auto_text then
            local limit = auto_text:match("limit:%s*(%d+)")
            if limit and tonumber(limit) > 10 then
              local r, c = auto_node:range()
              table.insert(diagnostics, {
                row = r,
                col = c,
                message = "Retry limit cannot exceed 10",
                severity = vim.diagnostic.severity.ERROR,
              })
            end
          end
        end
      end
    end
  end

  -- Validate required fields for specific step types
  if step_type and STEP_REQUIREMENTS[step_type] then
    for _, required_field in ipairs(STEP_REQUIREMENTS[step_type]) do
      if not fields[required_field] then
        table.insert(diagnostics, {
          row = row,
          col = col,
          message = string.format("'%s' step requires '%s' field", step_type, required_field),
          severity = vim.diagnostic.severity.ERROR,
        })
      end
    end
  end

  return diagnostics
end

---Validate the steps array
---@param steps_node TSNode
---@param bufnr number
---@return LintDiagnostic[]
local function validate_steps(steps_node, bufnr)
  local diagnostics = {}

  -- Steps should be a block_sequence
  local sequence_node = steps_node
  if steps_node:type() == "block_node" then
    sequence_node = find_child(steps_node, "block_sequence")
  end

  if not sequence_node or sequence_node:type() ~= "block_sequence" then
    local row, col = steps_node:range()
    table.insert(diagnostics, {
      row = row,
      col = col,
      message = "'steps' must be an array",
      severity = vim.diagnostic.severity.ERROR,
    })
    return diagnostics
  end

  local step_count = 0
  for child in sequence_node:iter_children() do
    if child:type() == "block_sequence_item" then
      step_count = step_count + 1

      -- Get the actual step content
      for item_child in child:iter_children() do
        if item_child:type() ~= "-" then
          local step_diags = validate_step(item_child, bufnr)
          vim.list_extend(diagnostics, step_diags)
        end
      end
    end
  end

  if step_count == 0 then
    local row, col = steps_node:range()
    table.insert(diagnostics, {
      row = row,
      col = col,
      message = "'steps' array must not be empty",
      severity = vim.diagnostic.severity.ERROR,
    })
  end

  return diagnostics
end

---Lint a buffer containing Buildkite pipeline YAML
---@param bufnr number|nil Buffer number (defaults to current)
---@return LintDiagnostic[]
function M.lint(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not M.has_yaml_parser() then
    vim.notify("YAML treesitter parser not installed. Run :TSInstall yaml", vim.log.levels.ERROR)
    return {}
  end

  local diagnostics = {}

  -- Get the syntax tree
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "yaml")
  if not ok or not parser then
    vim.notify("Failed to parse YAML", vim.log.levels.ERROR)
    return {}
  end

  local tree = parser:parse()[1]
  if not tree then
    return {}
  end

  local root = tree:root()

  -- Find the top-level document
  local document = nil
  for child in root:iter_children() do
    if child:type() == "document" then
      document = child
      break
    end
  end

  if not document then
    return {}
  end

  -- Find the block_node containing the top-level mapping
  local block_node = find_child(document, "block_node")
  if not block_node then
    return {}
  end

  local mapping = find_child(block_node, "block_mapping")
  if not mapping then
    return {}
  end

  local top_level = extract_mapping(mapping, bufnr)

  -- Check for required 'steps' key
  if not top_level["steps"] then
    table.insert(diagnostics, {
      row = 0,
      col = 0,
      message = "Pipeline must have a 'steps' key",
      severity = vim.diagnostic.severity.ERROR,
    })
  else
    -- Validate steps
    local steps_diags = validate_steps(top_level["steps"], bufnr)
    vim.list_extend(diagnostics, steps_diags)
  end

  return diagnostics
end

---Lint current buffer and show diagnostics
---@param bufnr number|nil
function M.lint_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Clear existing diagnostics
  vim.diagnostic.reset(NAMESPACE, bufnr)

  local diags = M.lint(bufnr)

  if #diags == 0 then
    vim.notify("Pipeline is valid", vim.log.levels.INFO)
    return
  end

  -- Convert to vim.diagnostic format
  local vim_diags = {}
  for _, d in ipairs(diags) do
    table.insert(vim_diags, {
      lnum = d.row,
      col = d.col,
      end_lnum = d.end_row,
      end_col = d.end_col,
      message = d.message,
      severity = d.severity,
      source = "buildkite",
    })
  end

  vim.diagnostic.set(NAMESPACE, bufnr, vim_diags)

  local error_count = #vim.tbl_filter(function(d)
    return d.severity == vim.diagnostic.severity.ERROR
  end, diags)

  local warn_count = #diags - error_count

  vim.notify(
    string.format("Pipeline lint: %d error(s), %d warning(s)", error_count, warn_count),
    error_count > 0 and vim.log.levels.ERROR or vim.log.levels.WARN
  )
end

return M
