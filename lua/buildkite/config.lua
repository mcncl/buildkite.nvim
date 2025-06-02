local path = require("plenary.path")

-- Check if plenary.json is available and get the correct encode function
local json_encode, json_decode

local function setup_json_functions()
    local has_plenary_json, plenary_json = pcall(require, "plenary.json")
    
    if has_plenary_json and plenary_json then
        -- Try different possible function names in plenary.json
        local encode_candidates = {
            plenary_json.encode,
            plenary_json.json_encode, 
            plenary_json.to_json,
            plenary_json.stringify
        }
        
        local decode_candidates = {
            plenary_json.decode,
            plenary_json.json_decode,
            plenary_json.from_json,
            plenary_json.parse
        }
        
        -- Find working encode function
        for _, encode_fn in ipairs(encode_candidates) do
            if type(encode_fn) == "function" then
                local test_ok, test_result = pcall(encode_fn, {test = "data"})
                if test_ok and type(test_result) == "string" then
                    json_encode = encode_fn
                    break
                end
            end
        end
        
        -- Find working decode function  
        for _, decode_fn in ipairs(decode_candidates) do
            if type(decode_fn) == "function" then
                local test_ok, test_result = pcall(decode_fn, '{"test":"data"}')
                if test_ok and type(test_result) == "table" then
                    json_decode = decode_fn
                    break
                end
            end
        end
    end
    
    -- Fallback to vim.json or vim.fn functions
    if not json_encode then
        if vim.json and vim.json.encode then
            json_encode = vim.json.encode
        elseif vim.fn.json_encode then
            json_encode = vim.fn.json_encode
        else
            -- Last resort: manual JSON for simple cases
            json_encode = function(data)
                if type(data) == "table" and next(data) == nil then
                    return "{}"
                end
                error("No JSON encode function available")
            end
        end
    end
    
    if not json_decode then
        if vim.json and vim.json.decode then
            json_decode = vim.json.decode
        elseif vim.fn.json_decode then
            json_decode = vim.fn.json_decode
        else
            json_decode = function(str)
                if str == "{}" then
                    return {}
                end
                error("No JSON decode function available")
            end
        end
    end
end

setup_json_functions()

local M = {}

-- Default configuration
local default_config = {
    api = {
        endpoint = "https://api.buildkite.com/v2",
        timeout = 10000,
    },
    organizations = {},
    current_organization = nil,
    ui = {
        split_direction = "horizontal",
        split_size = 15,
        auto_close = true,
        icons = {
            passed = "✓",
            failed = "✗",
            running = "●",
            scheduled = "○",
            canceled = "◎",
            skipped = "◌",
            blocked = "⏸",
        },
    },
    notifications = {
        enabled = true,
        build_complete = true,
        build_failed = true,
    },
}

-- Get the plugin data directory
local function get_data_dir()
    local data_path = vim.fn.stdpath("data")
    return path:new(data_path, "buildkite.nvim")
end

-- Get the global config file path
local function get_global_config_path()
    return get_data_dir():joinpath("config.json")
end

-- Get the project config file path for current working directory
local function get_project_config_path(cwd)
    cwd = cwd or vim.fn.getcwd()
    local hash = vim.fn.sha256(cwd)
    return get_data_dir():joinpath("projects", hash .. ".json")
end

-- Ensure data directory exists
local function ensure_data_dir()
    local data_dir = get_data_dir()
    if not data_dir:exists() then
        local ok, err = pcall(function()
            data_dir:mkdir({parents = true})
        end)
        if not ok then
            vim.notify("Failed to create data directory: " .. tostring(err), vim.log.levels.ERROR)
            vim.notify("Debug: Data dir path: " .. tostring(data_dir), vim.log.levels.DEBUG)
            return false
        end
    end
    
    local projects_dir = data_dir:joinpath("projects")
    if not projects_dir:exists() then
        local ok, err = pcall(function()
            projects_dir:mkdir({parents = true})
        end)
        if not ok then
            vim.notify("Failed to create projects directory: " .. tostring(err), vim.log.levels.ERROR)
            vim.notify("Debug: Projects dir path: " .. tostring(projects_dir), vim.log.levels.DEBUG)
            return false
        end
    end
    
    return true
end

-- Deep merge two tables
local function deep_merge(base, override)
    local result = vim.deepcopy(base)
    
    for key, value in pairs(override) do
        if type(value) == "table" and type(result[key]) == "table" then
            result[key] = deep_merge(result[key], value)
        else
            result[key] = value
        end
    end
    
    return result
end

-- Load global configuration
function M.load_global_config()
    local config_path = get_global_config_path()
    local base_config = vim.deepcopy(default_config)
    
    if not config_path:exists() then
        return base_config
    end
    
    local ok, content = pcall(function()
        return config_path:read()
    end)
    
    if not ok then
        vim.notify("Failed to read global config file", vim.log.levels.WARN)
        return base_config
    end
    
    local ok_json, saved_config = pcall(json_decode, content)
    if not ok_json then
        vim.notify("Failed to parse global config JSON", vim.log.levels.WARN)
        return base_config
    end
    
    -- Only merge the serializable parts
    if saved_config.organizations then
        base_config.organizations = saved_config.organizations
    end
    if saved_config.current_organization then
        base_config.current_organization = saved_config.current_organization
    end
    
    return base_config
end

-- Extract only serializable configuration data
local function get_serializable_config(config)
    return {
        organizations = config.organizations or {},
        current_organization = config.current_organization,
    }
end

-- Save global configuration
function M.save_global_config(config)
    if not ensure_data_dir() then
        return false
    end
    local config_path = get_global_config_path()
    
    -- Only save serializable parts
    local serializable_config = get_serializable_config(config)
    
    local ok, encoded = pcall(json_encode, serializable_config)
    if not ok then
        vim.notify("Failed to encode config to JSON: " .. tostring(encoded), vim.log.levels.ERROR)
        vim.notify("Debug: Config data: " .. vim.inspect(serializable_config), vim.log.levels.DEBUG)
        return false
    end
    
    local ok_write, write_err = pcall(function()
        config_path:write(encoded, "w")
    end)
    
    if not ok_write then
        vim.notify("Failed to write global config file: " .. tostring(write_err), vim.log.levels.ERROR)
        vim.notify("Debug: Config path: " .. tostring(config_path), vim.log.levels.DEBUG)
        return false
    end
    
    return true
end

-- Load project-specific configuration
function M.load_project_config(cwd)
    local config_path = get_project_config_path(cwd)
    
    if not config_path:exists() then
        return {}
    end
    
    local ok, content = pcall(function()
        return config_path:read()
    end)
    
    if not ok then
        vim.notify("Failed to read project config file", vim.log.levels.WARN)
        return {}
    end
    
    local ok_json, config = pcall(json_decode, content)
    if not ok_json then
        vim.notify("Failed to parse project config JSON", vim.log.levels.WARN)
        return {}
    end
    
    return config
end

-- Save project-specific configuration
function M.save_project_config(config, cwd)
    if not ensure_data_dir() then
        return false
    end
    local config_path = get_project_config_path(cwd)
    
    -- Project config should only contain simple data
    local project_config = {
        organization = config.organization,
        pipeline = config.pipeline,
        branch = config.branch,
        cwd = config.cwd,
    }
    
    local ok, encoded = pcall(json_encode, project_config)
    if not ok then
        vim.notify("Failed to encode project config to JSON: " .. tostring(encoded), vim.log.levels.ERROR)
        vim.notify("Debug: Project config data: " .. vim.inspect(project_config), vim.log.levels.DEBUG)
        return false
    end
    
    local ok_write, write_err = pcall(function()
        config_path:write(encoded, "w")
    end)
    
    if not ok_write then
        vim.notify("Failed to write project config file: " .. tostring(write_err), vim.log.levels.ERROR)
        vim.notify("Debug: Project config path: " .. tostring(config_path), vim.log.levels.DEBUG)
        return false
    end
    
    return true
end

-- Get merged configuration (global + project-specific)
function M.get_config(cwd)
    local global_config = M.load_global_config()
    local project_config = M.load_project_config(cwd)
    
    return deep_merge(global_config, project_config)
end

-- Add or update an organization configuration
function M.add_organization(name, token, opts)
    opts = opts or {}
    
    -- Validate inputs
    if not name or name == "" then
        return false, "Organization name cannot be empty"
    end
    if not token or token == "" then
        return false, "API token cannot be empty"
    end
    
    local global_config = M.load_global_config()
    
    global_config.organizations[name] = {
        token = token,
        repositories = opts.repositories or {},
    }
    
    -- If this is the first organization or set_current is true, make it current
    if vim.tbl_count(global_config.organizations) == 1 or opts.set_current or not global_config.current_organization then
        global_config.current_organization = name
    end
    
    local success = M.save_global_config(global_config)
    if success then
        return true, nil
    else
        return false, "Failed to save configuration"
    end
end

-- Remove an organization configuration
function M.remove_organization(name)
    local global_config = M.load_global_config()
    global_config.organizations[name] = nil
    
    -- If we're removing the current organization, switch to another one
    if global_config.current_organization == name then
        local remaining_orgs = vim.tbl_keys(global_config.organizations)
        global_config.current_organization = remaining_orgs[1] or nil
    end
    
    return M.save_global_config(global_config)
end

-- Set pipeline for current project (uses current organization if org_name not provided)
function M.set_project_pipeline(pipeline_slug, cwd, org_name)
    local project_config = M.load_project_config(cwd)
    
    -- Use provided org_name or fall back to current organization
    if not org_name then
        org_name = M.get_current_organization()
        if not org_name then
            return false, "No current organization set"
        end
    end
    
    project_config.organization = org_name
    project_config.pipeline = pipeline_slug
    project_config.cwd = cwd or vim.fn.getcwd()
    
    return M.save_project_config(project_config, cwd), nil
end

-- Get pipeline for current project
function M.get_project_pipeline(cwd)
    local project_config = M.load_project_config(cwd)
    return project_config.organization, project_config.pipeline
end

-- Set manual branch override for current project
function M.set_project_branch(branch_name, cwd)
    local project_config = M.load_project_config(cwd)
    project_config.branch = branch_name
    project_config.cwd = cwd or vim.fn.getcwd()
    return M.save_project_config(project_config, cwd), nil
end

-- Get manual branch override for current project
function M.get_project_branch(cwd)
    local project_config = M.load_project_config(cwd)
    return project_config.branch
end

-- Unset manual branch override for current project
function M.unset_project_branch(cwd)
    local project_config = M.load_project_config(cwd)
    project_config.branch = nil
    return M.save_project_config(project_config, cwd), nil
end

-- Unset pipeline for current project
function M.unset_project_pipeline(cwd)
    cwd = cwd or vim.fn.getcwd()
    local config_path = get_project_config_path(cwd)
    
    if not config_path:exists() then
        return true, nil -- Already unset
    end
    
    local ok, err = pcall(function()
        config_path:rm()
    end)
    
    if not ok then
        return false, "Failed to remove project configuration: " .. tostring(err)
    end
    
    return true, nil
end

-- Get organization configuration by name
function M.get_organization(name)
    local global_config = M.load_global_config()
    return global_config.organizations[name]
end

-- Get current organization
function M.get_current_organization()
    local global_config = M.load_global_config()
    
    local current_org = global_config.current_organization
    if current_org and global_config.organizations[current_org] then
        return current_org, global_config.organizations[current_org]
    end
    
    -- If no current org is set or it doesn't exist, return the first available one
    for name, org_config in pairs(global_config.organizations) do
        global_config.current_organization = name
        M.save_global_config(global_config)
        return name, org_config
    end
    
    return nil, nil
end

-- Set current organization
function M.set_current_organization(name)
    local global_config = M.load_global_config()
    
    if not global_config.organizations[name] then
        return false, string.format("Organization '%s' not found", name)
    end
    
    global_config.current_organization = name
    return M.save_global_config(global_config), nil
end

-- List all organizations
function M.list_organizations()
    local global_config = M.load_global_config()
    return global_config.organizations
end

-- Validate configuration
function M.validate_config(config)
    if not config.organizations or vim.tbl_isempty(config.organizations) then
        return false, "No organizations configured"
    end
    
    for name, org_config in pairs(config.organizations) do
        if not org_config.token or org_config.token == "" then
            return false, string.format("Organization '%s' has no API token", name)
        end
    end
    
    return true, nil
end

-- Initialize the configuration system
function M.setup(user_config)
    user_config = user_config or {}
    
    local global_config = M.load_global_config()
    local merged_config = deep_merge(global_config, user_config)
    
    -- Only save if user provided organizations or current_organization
    if user_config.organizations or user_config.current_organization then
        M.save_global_config(merged_config)
    end
    
    local ok, err = M.validate_config(merged_config)
    if not ok then
        vim.notify("Buildkite configuration error: " .. err, vim.log.levels.WARN)
    end
    
    return merged_config
end

return M