local M = {}

-- Import modules
local config_module = require("buildkite.config")
local api = require("buildkite.api")
local commands = require("buildkite.commands")

-- Plugin state
local initialized = false
local build_cache = {}
local pending_fetches = {}
local pending_timers = {}

-- Default configuration
local default_config = {
    organizations = {
        -- Example configuration:
        -- ["my-org"] = {
        --     token = "bkua_your_token_here",
        --     repositories = {},  -- Optional: filter to specific repos
        -- }
    },
    current_organization = nil, -- Name of the currently active organization
    api = {
        endpoint = "https://api.buildkite.com/v2",
        timeout = 10000,
    },
    ui = {
        split_direction = "horizontal", -- "horizontal" or "vertical"
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
            unblocked = "▶",
        },
    },
    notifications = {
        enabled = true,
        build_complete = true,
        build_failed = true,
        level = vim.log.levels.INFO,
    },
    keymaps = {
        enabled = true,
        prefix = "<leader>bk",
        mappings = {
            current_build = "c",
            current_pipeline = "cp",
            list_builds = "l",
            open_build = "o",
            rebuild_build = "r",
            set_pipeline = "p",
            org_list = "ol",
            org_switch = "os",
            branch_set = "bs",
            branch_unset = "bu",
            branch_info = "bi",
        }
    },
    auto_setup = {
        enabled = true,
        detect_git_repo = true,
        suggest_pipeline = true,
    },
    cache = {
        build_duration = 60000, -- Cache build status for 60 seconds (in milliseconds)
    }
}

-- Setup function
function M.setup(user_config)
    if initialized then
        vim.notify("Buildkite.nvim already initialized", vim.log.levels.WARN)
        return
    end

    user_config = user_config or {}

    -- Merge user config with defaults
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

    local merged_config = deep_merge(default_config, user_config)

    -- Initialize configuration system
    local config = config_module.setup(merged_config)

    -- Initialize API with config
    api.setup(merged_config)

    -- Setup commands
    commands.setup_commands()

    -- Setup keymaps if enabled
    if merged_config.keymaps.enabled then
        M.setup_keymaps(merged_config.keymaps)
    end

    -- Setup autocommands
    M.setup_autocommands(merged_config)

    initialized = true

    -- Validate configuration
    local ok, err = config_module.validate_config(config)
    if not ok then
        vim.notify("Buildkite configuration warning: " .. err, vim.log.levels.WARN)
        vim.notify("Use :Buildkite org add to configure organizations", vim.log.levels.INFO)
    end
end

-- Setup keymaps
function M.setup_keymaps(keymap_config)
    local prefix = keymap_config.prefix
    local mappings = keymap_config.mappings

    -- Helper function to create keymap
    local function map(key, cmd, desc)
        vim.keymap.set('n', prefix .. key, cmd, {
            desc = "Buildkite: " .. desc,
            silent = true
        })
    end

    -- Set up individual keymaps
    if mappings.current_build then
        map(mappings.current_build, function()
            commands.show_current_build()
        end, "Show current build")
    end

    if mappings.current_pipeline then
        map(mappings.current_pipeline, function()
            commands.get_pipeline_info()
        end, "Show current pipeline")
    end

    if mappings.list_builds then
        map(mappings.list_builds, function()
            commands.show_builds()
        end, "List builds")
    end

    if mappings.open_build then
        map(mappings.open_build, function()
            commands.open_build_url()
        end, "Open build in browser")
    end

    if mappings.set_pipeline then
        map(mappings.set_pipeline, function()
            commands.set_pipeline()
        end, "Set pipeline")
    end

    if mappings.org_list then
        map(mappings.org_list, function()
            commands.list_organizations()
        end, "List organizations")
    end

    if mappings.rebuild_build then
        map(mappings.rebuild_build, function()
            commands.rebuild_current_build()
        end, "Rebuild current build")
    end

    if mappings.org_switch then
        map(mappings.org_switch, function()
            commands.switch_organization()
        end, "Switch organization")
    end

    if mappings.branch_set then
        map(mappings.branch_set, function()
            commands.set_branch()
        end, "Set branch")
    end

    if mappings.branch_unset then
        map(mappings.branch_unset, function()
            commands.unset_branch()
        end, "Unset branch")
    end

    if mappings.branch_info then
        map(mappings.branch_info, function()
            commands.show_branch_info()
        end, "Show branch info")
    end
end

-- Setup autocommands
function M.setup_autocommands(config)
    local group = vim.api.nvim_create_augroup("BuildkiteNvim", { clear = true })

    -- Status line integration (optional)
    if config.ui.statusline_integration then
        vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
            group = group,
            callback = function()
                -- This could be used to update statusline with build status
                -- Implementation depends on user's statusline plugin
            end,
        })
    end

    -- Cleanup pending requests on exit to prevent hanging
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            -- Cancel all pending timers
            for cache_key, timer in pairs(pending_timers) do
                if timer then
                    vim.fn.timer_stop(timer)
                end
            end
            -- Clear all pending fetches and timers
            pending_fetches = {}
            pending_timers = {}
        end,
    })
end

-- Utility functions
function M.get_current_build()
    local git = require("buildkite.git")
    local cwd = vim.fn.getcwd()

    -- Get effective branch (manual override or Git-detected)
    local manual_branch = config_module.get_project_branch(cwd)
    local branch
    if manual_branch then
        branch = manual_branch
    else
        -- Check if we're in a git repository for fallback
        if not git.is_git_repo(cwd) then
            return nil, "Not a git repository and no manual branch set"
        end

        branch = git.get_current_branch(cwd)
        if not branch then
            return nil, "Could not determine current git branch and no manual branch set"
        end
    end

    -- Get project pipeline configuration
    local org_name, pipeline_slug = config_module.get_project_pipeline(cwd)
    if not org_name or not pipeline_slug then
        return nil, "No pipeline configured"
    end

    -- Create cache key
    local cache_key = string.format("%s/%s/%s", org_name, pipeline_slug, branch)
    local now = vim.loop.now()
    local config = M.get_config()
    local cache_duration = (config.cache and config.cache.build_duration) or 60000

    -- Check cache
    if build_cache[cache_key] and
        build_cache[cache_key].timestamp and
        (now - build_cache[cache_key].timestamp) < cache_duration then
        return build_cache[cache_key].build, build_cache[cache_key].error
    end

    -- If we're already fetching this build, return loading state
    if pending_fetches[cache_key] then
        return nil, "Loading..."
    end

    -- Start async fetch to avoid blocking
    pending_fetches[cache_key] = true
    local timer = vim.defer_fn(function()
        local ok, build, err = pcall(function()
            return api.get_current_project_build(cwd, branch)
        end)

        if not ok then
            build, err = nil, build -- pcall puts error in second return value
        end

        -- Cache the result
        build_cache[cache_key] = {
            build = build,
            error = err,
            timestamp = vim.loop.now()
        }

        -- Clear pending flag and timer
        pending_fetches[cache_key] = nil
        pending_timers[cache_key] = nil

        -- Trigger statusline refresh if lualine is available
        local has_lualine, lualine = pcall(require, "lualine")
        if has_lualine and lualine.refresh then
            lualine.refresh()
        end
    end, 100) -- Small delay to avoid blocking startup

    -- Store timer handle for cleanup
    pending_timers[cache_key] = timer

    -- Return loading state immediately
    return nil, "Loading..."
end

-- Clear build cache (useful for debugging or manual refresh)
function M.clear_build_cache()
    build_cache = {}
end

-- Force refresh current build (clears cache and fetches new data)
function M.refresh_current_build()
    M.clear_build_cache()
    return M.get_current_build()
end

function M.get_config()
    return config_module.get_config()
end

function M.is_initialized()
    return initialized
end

-- Health check function for :checkhealth
function M.health()
    local health_start = vim.health.start or vim.health.report_start
    local health_ok = vim.health.ok or vim.health.report_ok
    local health_error = vim.health.error or vim.health.report_error
    local health_warn = vim.health.warn or vim.health.report_warn

    health_start("Buildkite.nvim")

    -- Check if plugin is initialized
    if not initialized then
        health_error("Plugin not initialized. Call require('buildkite').setup()")
        return
    end

    health_ok("Plugin initialized")

    -- Check dependencies
    local has_plenary = pcall(require, "plenary")
    if has_plenary then
        health_ok("plenary.nvim found")
    else
        health_error("plenary.nvim not found. Install with your plugin manager.")
    end

    -- Check configuration
    local config = config_module.get_config()
    local ok, err = config_module.validate_config(config)

    if ok then
        health_ok("Configuration valid")

        -- Check organizations
        local orgs = config_module.list_organizations()
        local org_count = vim.tbl_count(orgs)

        if org_count > 0 then
            health_ok(string.format("%d organization(s) configured", org_count))

            -- Check if we have a current organization
            local current_org = config_module.get_current_organization()
            if current_org then
                health_ok(string.format("Current organization: %s", current_org))
            else
                health_warn("No current organization set")
            end
        else
            health_warn("No organizations configured")
        end
    else
        health_error("Configuration error: " .. err)
    end

    -- Check current project
    local git = require("buildkite.git")
    if git.is_git_repo() then
        health_ok("Current directory is a git repository")

        local branch = git.get_current_branch()
        if branch then
            health_ok(string.format("Current branch: %s", branch))
        else
            health_warn("Could not determine current branch")
        end

        local org_name, pipeline_slug = config_module.get_project_pipeline()
        if org_name and pipeline_slug then
            health_ok(string.format("Pipeline configured: %s/%s", org_name, pipeline_slug))
        else
            health_warn("No pipeline configured for current project")
        end
    else
        health_warn("Current directory is not a git repository")
    end
end

-- Export main functions for easier access
M.commands = commands
M.config = config_module
M.api = api

return M
