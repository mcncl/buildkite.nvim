local M = {}

local function health_start(msg)
    if vim.health.start then
        vim.health.start(msg)
    else
        vim.health.report_start(msg)
    end
end

local function health_ok(msg)
    if vim.health.ok then
        vim.health.ok(msg)
    else
        vim.health.report_ok(msg)
    end
end

local function health_warn(msg)
    if vim.health.warn then
        vim.health.warn(msg)
    else
        vim.health.report_warn(msg)
    end
end

local function health_error(msg)
    if vim.health.error then
        vim.health.error(msg)
    else
        vim.health.report_error(msg)
    end
end

local function health_info(msg)
    if vim.health.info then
        vim.health.info(msg)
    else
        vim.health.report_info(msg)
    end
end

function M.check()
    health_start("buildkite.nvim")

    -- Check if plugin is initialized
    local buildkite = require("buildkite")
    if not buildkite.is_initialized() then
        health_error("Plugin not initialized. Call require('buildkite').setup()")
        return
    end

    health_ok("Plugin initialized")

    -- Check dependencies
    health_start("Dependencies")

    local has_plenary, _ = pcall(require, "plenary")
    if has_plenary then
        health_ok("plenary.nvim found")
    else
        health_error("plenary.nvim not found. Install with your plugin manager.")
        health_info("Install: https://github.com/nvim-lua/plenary.nvim")
        return
    end

    -- Check plenary components
    local has_async = pcall(require, "plenary.async")
    local has_curl = pcall(require, "plenary.curl")
    local has_json = pcall(require, "plenary.json")
    local has_path = pcall(require, "plenary.path")

    if has_async and has_curl and has_json and has_path then
        health_ok("All plenary components available")
    else
        health_warn("Some plenary components missing")
        if not has_async then health_info("Missing: plenary.async") end
        if not has_curl then health_info("Missing: plenary.curl") end
        if not has_json then health_info("Missing: plenary.json") end
        if not has_path then health_info("Missing: plenary.path") end
    end

    -- Check configuration
    health_start("Configuration")

    local config_module = require("buildkite.config")
    local config = config_module.get_config()
    local ok, err = config_module.validate_config(config)

    if ok then
        health_ok("Configuration valid")
    else
        health_error("Configuration error: " .. err)
        health_info("Use :Buildkite org add to configure organizations")
    end

    -- Check organizations
    health_start("Organizations")

    local orgs = config_module.list_organizations()
    local org_count = vim.tbl_count(orgs)

    if org_count > 0 then
        health_ok(string.format("%d organization(s) configured", org_count))

        -- List organizations
        local current_org = config_module.get_current_organization()
        for name, org_config in pairs(orgs) do
            local current_marker = (name == current_org) and " (current)" or ""
            local repo_count = org_config.repositories and #org_config.repositories or 0
            health_info(string.format("  %s%s - %d repositories", name, current_marker, repo_count))
        end

        -- Check if we have a current organization
        current_org = config_module.get_current_organization()
        if current_org then
            health_ok(string.format("Current organization: %s", current_org))
        else
            health_warn("No current organization set")
            health_info("Set current with :Buildkite org add or :Buildkite org switch")
        end
    else
        health_warn("No organizations configured")
        health_info("Use :Buildkite org add to add organizations")
    end

    -- Check current project
    health_start("Current Project")

    local git = require("buildkite.git")
    local cwd = vim.fn.getcwd()

    if git.is_git_repo(cwd) then
        health_ok("Current directory is a git repository")

        local branch = git.get_current_branch(cwd)
        if branch then
            health_ok(string.format("Current branch: %s", branch))
        else
            health_warn("Could not determine current branch")
            health_info("Make sure you're on a valid git branch")
        end

        local repo_name = git.get_repo_name(cwd)
        if repo_name then
            health_info(string.format("Repository: %s", repo_name))
        end

        local org_name, pipeline_slug = config_module.get_project_pipeline(cwd)
        if org_name and pipeline_slug then
            health_ok(string.format("Pipeline configured: %s/%s", org_name, pipeline_slug))
        else
            health_warn("No pipeline configured for current project")
            health_info("Use :Buildkite pipeline set to configure")
        end

        -- Check for uncommitted changes
        if git.has_uncommitted_changes(cwd) then
            health_info("Working directory has uncommitted changes")
        end
    else
        health_info("Current directory is not a git repository")
        health_info("Navigate to a git repository to use build features")
    end

    -- Check API connectivity (if we have configuration)
    if org_count > 0 then
        health_start("API Connectivity")

        -- Try to test API with the current organization
        local current_org, current_org_config = config_module.get_current_organization()
        if current_org and current_org_config then
            health_info(string.format("Testing API connectivity for '%s'...", current_org))

            -- Simple async test
            local api = require("buildkite.api")
            local async = require("plenary.async")

            local test_result = async.run(function()
                local api_ok, result = pcall(function()
                    return async.wait(api.get_pipelines(current_org))
                end)
                return api_ok, result
            end)

            if test_result then
                health_ok("API connection successful")
            else
                health_warn("API connection failed")
                health_info("Check your API token and network connection")
                health_info("Token scopes needed: read_builds, read_pipelines, read_organizations")
            end
        end
    end

    -- Check for external tools
    health_start("External Tools")

    -- Check git
    local git_available = vim.fn.executable("git") == 1
    if git_available then
        health_ok("git command available")
    else
        health_error("git command not found")
        health_info("Git is required for repository detection")
    end

    -- Check for browser opening capability
    local open_cmd = nil
    if vim.fn.has("mac") == 1 then
        open_cmd = "open"
    elseif vim.fn.has("unix") == 1 then
        open_cmd = "xdg-open"
    elseif vim.fn.has("win32") == 1 then
        open_cmd = "start"
    end

    if open_cmd and vim.fn.executable(open_cmd) == 1 then
        health_ok(string.format("Browser opening available (%s)", open_cmd))
    else
        health_warn("No browser opening command found")
        health_info("Build URLs can still be copied manually")
    end

    -- Configuration paths info
    health_start("File Locations")

    local data_dir = vim.fn.stdpath("data") .. "/buildkite.nvim"
    health_info("Configuration directory: " .. data_dir)

    local global_config_path = data_dir .. "/config.json"
    if vim.fn.filereadable(global_config_path) == 1 then
        health_info("Global config: " .. global_config_path .. " ✓")
    else
        health_info("Global config: " .. global_config_path .. " (not found)")
    end

    local projects_dir = data_dir .. "/projects"
    if vim.fn.isdirectory(projects_dir) == 1 then
        local project_files = vim.fn.glob(projects_dir .. "/*.json", false, true)
        health_info(string.format("Project configs: %d found", #project_files))
    else
        health_info("Project configs: none found")
    end
end

return M
