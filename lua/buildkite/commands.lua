local config_module = require("buildkite.config")
local api = require("buildkite.api")
local git = require("buildkite.git")

local M = {}

-- Helper function to create selection menu
local function create_selection_menu(items, prompt, format_fn)
    format_fn = format_fn or function(item) return tostring(item) end
    
    local formatted_items = {}
    for i, item in ipairs(items) do
        table.insert(formatted_items, string.format("%d. %s", i, format_fn(item)))
    end
    
    local choice = vim.fn.inputlist(vim.list_extend({prompt}, formatted_items))
    if choice > 0 and choice <= #items then
        return items[choice]
    end
    return nil
end

-- Helper function to get current project info
-- Get effective branch (manual override or Git-detected)
local function get_effective_branch(cwd)
    -- First check for manual branch override
    local manual_branch = config_module.get_project_branch(cwd)
    if manual_branch then
        return manual_branch, "manual"
    end
    
    -- Fall back to Git detection
    local git_branch = git.get_current_branch(cwd)
    if git_branch then
        return git_branch, "git"
    end
    
    return nil, "none"
end

-- Helper function to get project information
function get_project_info(cwd)
    cwd = cwd or vim.fn.getcwd()
    local branch, branch_source = get_effective_branch(cwd)
    local git_branch = git.get_current_branch(cwd)
    local manual_branch = config_module.get_project_branch(cwd)
    local repo_name = git.get_repo_name(cwd)
    local org_name, pipeline_slug = config_module.get_project_pipeline(cwd)
    
    return {
        cwd = cwd,
        branch = branch,
        branch_source = branch_source,
        git_branch = git_branch,
        manual_branch = manual_branch,
        repo_name = repo_name,
        org_name = org_name,
        pipeline_slug = pipeline_slug,
        is_git_repo = git.is_git_repo(cwd)
    }
end

-- Organization management commands
function M.add_organization()
    local org_name = vim.fn.input("Organization name: ")
    if org_name == "" then
        vim.notify("Organization name cannot be empty", vim.log.levels.WARN)
        return
    end
    
    local token = vim.fn.input("API token: ")
    if token == "" then
        vim.notify("API token cannot be empty", vim.log.levels.WARN)
        return
    end
    
    local set_current = vim.fn.confirm("Set as current organization?", "&Yes\n&No", 1) == 1
    
    local success, err = config_module.add_organization(org_name, token, { set_current = set_current })
    if success then
        vim.notify(string.format("Organization '%s' added successfully", org_name), vim.log.levels.INFO)
        if set_current then
            vim.notify(string.format("Current organization set to '%s'", org_name), vim.log.levels.INFO)
        end
    else
        vim.notify("Failed to add organization: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
end

function M.remove_organization(org_name)
    if not org_name then
        local orgs = config_module.list_organizations()
        local org_names = vim.tbl_keys(orgs)
        
        if #org_names == 0 then
            vim.notify("No organizations configured", vim.log.levels.WARN)
            return
        end
        
        org_name = create_selection_menu(org_names, "Select organization to remove:")
        if not org_name then
            return
        end
    end
    
    local confirm = vim.fn.confirm(
        string.format("Remove organization '%s'?", org_name),
        "&Yes\n&No", 2
    )
    
    if confirm == 1 then
        local success = config_module.remove_organization(org_name)
        if success then
            vim.notify(string.format("Organization '%s' removed", org_name), vim.log.levels.INFO)
        else
            vim.notify("Failed to remove organization", vim.log.levels.ERROR)
        end
    end
end

function M.list_organizations()
    local orgs = config_module.list_organizations()
    
    if vim.tbl_isempty(orgs) then
        vim.notify("No organizations configured", vim.log.levels.INFO)
        return
    end
    
    local current_org = config_module.get_current_organization()
    local lines = {"Configured organizations:"}
    for name, org_config in pairs(orgs) do
        local current_marker = (name == current_org) and " (current)" or ""
        local repo_count = org_config.repositories and #org_config.repositories or 0
        table.insert(lines, string.format("  %s%s - %d repositories", name, current_marker, repo_count))
    end
    
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.switch_organization(org_name)
    if not org_name then
        local orgs = config_module.list_organizations()
        local org_names = vim.tbl_keys(orgs)
        
        if #org_names == 0 then
            vim.notify("No organizations configured", vim.log.levels.WARN)
            return
        end
        
        if #org_names == 1 then
            vim.notify("Only one organization configured", vim.log.levels.INFO)
            return
        end
        
        local current_org = config_module.get_current_organization()
        org_name = create_selection_menu(org_names, "Select organization:", function(name)
            local current_marker = (name == current_org) and " (current)" or ""
            return name .. current_marker
        end)
        
        if not org_name then
            return
        end
    end
    
    local success, err = config_module.set_current_organization(org_name)
    if success then
        vim.notify(string.format("Switched to organization '%s'", org_name), vim.log.levels.INFO)
    else
        vim.notify("Failed to switch organization: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
end

function M.get_current_organization()
    local org_name, org_config = config_module.get_current_organization()
    if org_name then
        vim.notify(string.format("Current organization: %s", org_name), vim.log.levels.INFO)
    else
        vim.notify("No current organization set", vim.log.levels.WARN)
    end
end

-- Debug commands


function M.debug_config()
    local config = config_module.get_config()
    local lines = {
        "=== Buildkite Configuration Debug ===",
        "Organizations:",
    }
    
    for name, org_config in pairs(config.organizations or {}) do
        local current_marker = (name == config.current_organization) and " (current)" or ""
        local token_preview = org_config.token and (org_config.token:sub(1, 10) .. "...") or "no token"
        table.insert(lines, string.format("  %s%s - %s", name, current_marker, token_preview))
    end
    
    table.insert(lines, "")
    table.insert(lines, string.format("Current organization: %s", config.current_organization or "none"))
    table.insert(lines, string.format("Data directory: %s", vim.fn.stdpath("data") .. "/buildkite.nvim"))
    
    local project_info = get_project_info()
    table.insert(lines, "")
    table.insert(lines, "=== Current Project ===")
    table.insert(lines, string.format("Directory: %s", project_info.cwd))
    table.insert(lines, string.format("Git repo: %s", project_info.is_git_repo and "yes" or "no"))
    table.insert(lines, string.format("Effective branch: %s (%s)", project_info.branch or "unknown", project_info.branch_source))
    if project_info.git_branch then
        table.insert(lines, string.format("Git branch: %s", project_info.git_branch))
    end
    if project_info.manual_branch then
        table.insert(lines, string.format("Manual branch override: %s", project_info.manual_branch))
    end
    table.insert(lines, string.format("Configured org: %s", project_info.org_name or "none"))
    table.insert(lines, string.format("Configured pipeline: %s", project_info.pipeline_slug or "none"))
    
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.reset_config()
    local confirm = vim.fn.confirm(
        "This will delete ALL Buildkite configuration. Continue?",
        "&Yes\n&No", 2
    )
    
    if confirm ~= 1 then
        return
    end
    
    local data_dir = vim.fn.stdpath("data") .. "/buildkite.nvim"
    local cmd = string.format("rm -rf %s", vim.fn.shellescape(data_dir))
    
    local result = vim.fn.system(cmd)
    if vim.v.shell_error == 0 then
        vim.notify("Configuration reset successfully", vim.log.levels.INFO)
        vim.notify("Restart Neovim to reinitialize", vim.log.levels.INFO)
    else
        vim.notify("Failed to reset configuration: " .. result, vim.log.levels.ERROR)
    end
end



-- Pipeline management commands
function M.set_pipeline(pipeline_slug)
    local project_info = get_project_info()
    
    if not project_info.is_git_repo then
        vim.notify("Current directory is not a git repository", vim.log.levels.WARN)
        return
    end
    
    -- Get current organization
    local org_name, org_config = config_module.get_current_organization()
    if not org_name then
        vim.notify("No current organization set. Use :Buildkite org add or :Buildkite org switch", vim.log.levels.WARN)
        return
    end
    
    -- If no pipeline specified, prompt for input
    if not pipeline_slug then
        -- Suggest a default based on repository name if available
        local default_slug = ""
        if project_info.repo_name then
            default_slug = project_info.repo_name
        end
        
        local prompt_text = "Enter pipeline slug"
        if default_slug ~= "" then
            prompt_text = prompt_text .. " [" .. default_slug .. "]"
        end
        prompt_text = prompt_text .. ": "
        
        local ok, input_result = pcall(vim.fn.input, prompt_text)
        
        -- Clear the command line
        vim.cmd("redraw")
        
        if not ok then
            -- User cancelled with Ctrl+C
            vim.notify("Pipeline setup cancelled", vim.log.levels.INFO)
            return
        end
        
        pipeline_slug = input_result
        
        -- Use default if user entered nothing
        if not pipeline_slug or pipeline_slug == "" then
            if default_slug ~= "" then
                pipeline_slug = default_slug
            else
                vim.notify("Pipeline slug cannot be empty", vim.log.levels.WARN)
                return
            end
        end
    end
    
    -- Save the configuration
    local success, err = config_module.set_project_pipeline(pipeline_slug, project_info.cwd)
    if success then
        vim.notify(string.format("Pipeline set to '%s/%s'", org_name, pipeline_slug), vim.log.levels.INFO)
    else
        vim.notify("Failed to save pipeline configuration: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
end

function M.unset_pipeline()
    local project_info = get_project_info()
    
    if not project_info.is_git_repo then
        vim.notify("Current directory is not a git repository", vim.log.levels.WARN)
        return
    end

    -- Check if a pipeline is currently configured
    local org_name, pipeline_slug = config_module.get_project_pipeline(project_info.cwd)
    if not org_name or not pipeline_slug then
        vim.notify("No pipeline configured for current project", vim.log.levels.INFO)
        return
    end

    -- Confirm the action
    local confirm = vim.fn.confirm(
        string.format("Remove pipeline configuration '%s/%s' for this project?", org_name, pipeline_slug),
        "&Yes\n&No", 2
    )
    
    if confirm ~= 1 then
        return
    end

    -- Remove the pipeline configuration
    local success, err = config_module.unset_project_pipeline(project_info.cwd)
    if success then
        vim.notify("Pipeline configuration removed for current project", vim.log.levels.INFO)
    else
        vim.notify("Failed to remove pipeline configuration: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
end

function M.get_pipeline_info()
    local project_info = get_project_info()
    
    if not project_info.org_name or not project_info.pipeline_slug then
        vim.notify("No pipeline configured for current project", vim.log.levels.WARN)
        return
    end
    
    vim.notify(string.format("Current pipeline: %s/%s", project_info.org_name, project_info.pipeline_slug), vim.log.levels.INFO)
end

-- Build status commands
function M.show_current_build()
    local project_info = get_project_info()
    
    if not project_info.org_name or not project_info.pipeline_slug then
        vim.notify("No pipeline configured. Use :Buildkite pipeline set", vim.log.levels.WARN)
        return
    end
    
    if not project_info.branch then
        vim.notify("Could not determine current branch. Use :Buildkite branch set to set manually", vim.log.levels.WARN)
        return
    end
    
    vim.notify(string.format("Fetching build for branch '%s'...", project_info.branch), vim.log.levels.INFO)
    
    local ok, build, err = pcall(function()
        return api.get_current_project_build(project_info.cwd, project_info.branch)
    end)
    
    if not ok then
        vim.notify("Failed to fetch build: " .. build, vim.log.levels.ERROR)
        return
    end
    
    if err then
        vim.notify(err, vim.log.levels.ERROR)
        return
    end
    
    if not build then
        vim.notify(string.format("No builds found for branch '%s'", project_info.branch), vim.log.levels.INFO)
        return
    end
    
    local config = config_module.get_config()
    local status_icon = config.ui.icons[build.state] or "?"
    
    local info = {
        string.format("Build #%s - %s %s", build.number, status_icon, build.state),
        string.format("Branch: %s", build.branch),
        string.format("Commit: %s", build.commit:sub(1, 8)),
        string.format("Message: %s", build.message or "No message"),
        string.format("Author: %s", build.author and type(build.author) == "table" and build.author.name or "Unknown"),
        string.format("Created: %s", build.created_at),
        string.format("URL: %s", build.web_url)
    }
    
    vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
end

function M.show_builds(branch, limit)
    local project_info = get_project_info()
    branch = branch or project_info.branch
    limit = limit or 10
    
    if not project_info.org_name or not project_info.pipeline_slug then
        vim.notify("No pipeline configured. Use :Buildkite pipeline set", vim.log.levels.WARN)
        return
    end
    
    vim.notify(string.format("Fetching builds for branch '%s'...", branch), vim.log.levels.INFO)
    
    local ok, builds = pcall(function()
        return api.get_builds_for_branch(
            project_info.org_name, 
            project_info.pipeline_slug, 
            branch, 
            { per_page = limit }
        )
    end)
    
    if not ok then
        vim.notify("Failed to fetch builds: " .. builds, vim.log.levels.ERROR)
        return
    end
    
    if not builds or #builds == 0 then
        vim.notify(string.format("No builds found for branch '%s'", branch), vim.log.levels.INFO)
        return
    end
    
    local config = config_module.get_config()
    local lines = {string.format("Recent builds for branch '%s':", branch)}
    
    for _, build in ipairs(builds) do
        local status_icon = config.ui.icons[build.state] or "?"
        local commit_short = build.commit and build.commit:sub(1, 8) or "unknown"
        local message = build.message and build.message:sub(1, 50) or "No message"
        
        table.insert(lines, string.format("  #%s %s %s (%s) - %s", 
            build.number, status_icon, build.state, commit_short, message))
    end
    
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.open_build_url()
    local project_info = get_project_info()
    
    if not project_info.org_name or not project_info.pipeline_slug then
        vim.notify("No pipeline configured. Use :Buildkite pipeline set", vim.log.levels.WARN)
        return
    end
    
    if not project_info.branch then
        vim.notify("Could not determine current git branch", vim.log.levels.WARN)
        return
    end
    
    local ok, build, err = pcall(function()
        return api.get_current_project_build(project_info.cwd, project_info.branch)
    end)
    
    if not ok then
        vim.notify("Failed to fetch build: " .. build, vim.log.levels.ERROR)
        return
    end
    
    if err then
        vim.notify(err, vim.log.levels.ERROR)
        return
    end
    
    if not build then
        vim.notify(string.format("No builds found for branch '%s'", project_info.branch), vim.log.levels.INFO)
        return
    end
    
    if build.web_url then
        vim.fn.system(string.format("open '%s'", build.web_url))
        vim.notify("Opened build in browser", vim.log.levels.INFO)
    else
        vim.notify("No web URL available for this build", vim.log.levels.WARN)
    end
end

function M.refresh_current_build()
    local buildkite = require("buildkite")
    
    vim.notify("Refreshing current build status...", vim.log.levels.INFO)
    
    local ok, build, err = pcall(function()
        return buildkite.refresh_current_build()
    end)
    
    if not ok then
        vim.notify("Failed to refresh build: " .. build, vim.log.levels.ERROR)
        return
    end
    
    if build then
        local config = require("buildkite.config").get_config()
        local status_icon = config.ui.icons[build.state] or "?"
        vim.notify(string.format("Build refreshed: %s %s #%s", status_icon, build.state, build.number), vim.log.levels.INFO)
    else
        vim.notify("No build found for current branch", vim.log.levels.WARN)
    end
end

function M.rebuild_current_build()
    local project_info = get_project_info()
    
    if not project_info.org_name or not project_info.pipeline_slug then
        vim.notify("No pipeline configured. Use :Buildkite pipeline set", vim.log.levels.WARN)
        return
    end
    
    if not project_info.branch then
        vim.notify("Could not determine current branch. Use :Buildkite branch set to set manually", vim.log.levels.WARN)
        return
    end
    
    vim.notify(string.format("Finding latest build for branch '%s'...", project_info.branch), vim.log.levels.INFO)
    
    local ok, build = pcall(function()
        return api.get_latest_build_for_branch(project_info.org_name, project_info.pipeline_slug, project_info.branch)
    end)
    
    if not ok then
        vim.notify("Failed to fetch build: " .. build, vim.log.levels.ERROR)
        return
    end
    
    if not build then
        vim.notify("No builds found for current branch", vim.log.levels.WARN)
        return
    end
    
    vim.notify(string.format("Rebuilding build #%s...", build.number), vim.log.levels.INFO)
    
    local rebuild_ok, new_build = pcall(function()
        return api.rebuild(project_info.org_name, project_info.pipeline_slug, build.number)
    end)
    
    if not rebuild_ok then
        vim.notify("Failed to rebuild: " .. new_build, vim.log.levels.ERROR)
        return
    end
    
    vim.notify(string.format("Build #%s queued successfully! New build: #%s", 
        build.number, new_build.number), vim.log.levels.INFO)
    
    -- Immediately refresh the status line to show the new build
    local buildkite = require("buildkite")
    buildkite.refresh_current_build()
end

-- Set manual branch override
function M.set_branch(branch_name)
    if not branch_name or branch_name == "" then
        vim.ui.input({
            prompt = "Enter branch name: ",
        }, function(input)
            if input and input ~= "" then
                M.set_branch(input)
            end
        end)
        return
    end
    
    local success, err = config_module.set_project_branch(branch_name)
    if success then
        vim.notify(string.format("Manual branch set to: %s", branch_name), vim.log.levels.INFO)
        -- Clear build cache since branch changed
        local buildkite = require("buildkite")
        buildkite.clear_build_cache()
    else
        vim.notify("Failed to set branch: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
end

-- Unset manual branch override
function M.unset_branch()
    local success, err = config_module.unset_project_branch()
    if success then
        vim.notify("Manual branch override removed", vim.log.levels.INFO)
        -- Clear build cache since branch changed
        local buildkite = require("buildkite")
        buildkite.clear_build_cache()
    else
        vim.notify("Failed to unset branch: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
end

-- Show current branch information
function M.show_branch_info()
    local project_info = get_project_info()
    
    if project_info.branch then
        local status_msg = string.format("Current branch: %s (source: %s)", project_info.branch, project_info.branch_source)
        
        if project_info.branch_source == "manual" and project_info.git_branch then
            status_msg = status_msg .. string.format("\nGit branch: %s", project_info.git_branch)
        end
        
        vim.notify(status_msg, vim.log.levels.INFO)
    else
        vim.notify("No branch detected or configured", vim.log.levels.WARN)
    end
end

-- Setup command autocompletions and main command
function M.setup_commands()
    -- Main Buildkite command with subcommands
    vim.api.nvim_create_user_command("Buildkite", function(opts)
        local args = vim.split(opts.args, "%s+")
        local cmd = args[1]
        
        if cmd == "org" then
            local subcmd = args[2]
            if subcmd == "add" then
                M.add_organization()
            elseif subcmd == "remove" then
                M.remove_organization(args[3])
            elseif subcmd == "list" then
                M.list_organizations()
            elseif subcmd == "switch" then
                M.switch_organization(args[3])
            elseif subcmd == "current" then
                M.get_current_organization()
            else
                vim.notify("Usage: :Buildkite org [add|remove|list|switch|current] [name]", vim.log.levels.INFO)
            end
        elseif cmd == "debug" then
            local subcmd = args[2]
            if subcmd == "config" then
                M.debug_config()
            elseif subcmd == "reset" then
                M.reset_config()
            else
                vim.notify("Usage: :Buildkite debug [config|reset]", vim.log.levels.INFO)
            end
        elseif cmd == "pipeline" then
            local subcmd = args[2]
            if subcmd == "set" then
                M.set_pipeline(args[3])
            elseif subcmd == "unset" then
                M.unset_pipeline()
            elseif subcmd == "info" then
                M.get_pipeline_info()
            else
                vim.notify("Usage: :Buildkite pipeline [set|unset|info] [pipeline]", vim.log.levels.INFO)
            end
        elseif cmd == "build" then
            local subcmd = args[2]
            if subcmd == "current" then
                M.show_current_build()
            elseif subcmd == "list" then
                M.show_builds(args[3], tonumber(args[4]))
            elseif subcmd == "open" then
                M.open_build_url()
            elseif subcmd == "refresh" then
                M.refresh_current_build()
            elseif subcmd == "rebuild" then
                M.rebuild_current_build()
            else
                vim.notify("Usage: :Buildkite build [current|list|open|refresh|rebuild] [branch] [limit]", vim.log.levels.INFO)
            end
        elseif cmd == "branch" then
            local subcmd = args[2]
            if subcmd == "set" then
                M.set_branch(args[3])
            elseif subcmd == "unset" then
                M.unset_branch()
            elseif subcmd == "info" then
                M.show_branch_info()
            else
                vim.notify("Usage: :Buildkite branch [set|unset|info] [branch_name]", vim.log.levels.INFO)
            end
        else
            local help = {
                "Buildkite.nvim commands:",
                "  :Buildkite org add                    - Add organization",
                "  :Buildkite org remove [name]          - Remove organization", 
                "  :Buildkite org list                   - List organizations",
                "  :Buildkite org switch [name]          - Switch current organization",
                "  :Buildkite org current                - Show current organization",
                "  :Buildkite pipeline set [name]        - Set pipeline for project",
                "  :Buildkite pipeline unset             - Remove pipeline for project",
                "  :Buildkite pipeline info              - Show current pipeline",
                "  :Buildkite build current              - Show current branch build",
                "  :Buildkite build list [branch] [n]    - List recent builds",
                "  :Buildkite build open                 - Open build in browser",
                "  :Buildkite build refresh              - Refresh current build status",
                "  :Buildkite build rebuild              - Rebuild current branch build",
                "  :Buildkite branch set [name]          - Set manual branch override",
                "  :Buildkite branch unset               - Remove manual branch override",
                "  :Buildkite branch info                - Show current branch information",
                "  :Buildkite debug config               - Show debug information",
                "  :Buildkite debug reset                - Reset all configuration"
            }
            vim.notify(table.concat(help, "\n"), vim.log.levels.INFO)
        end
    end, {
        nargs = "*",
        complete = function(ArgLead, CmdLine, CursorPos)
            local args = vim.split(CmdLine, "%s+")
            local arg_count = #args
            
            -- Remove "Buildkite" from count
            if args[1] == "Buildkite" then
                arg_count = arg_count - 1
                table.remove(args, 1)
            end
            
            if arg_count == 1 then
                return vim.tbl_filter(function(item)
                    return vim.startswith(item, ArgLead)
                end, {"org", "pipeline", "build", "branch", "debug"})
            elseif arg_count == 2 then
                if args[1] == "org" then
                    return vim.tbl_filter(function(item)
                        return vim.startswith(item, ArgLead)
                    end, {"add", "remove", "list", "switch", "current"})
                elseif args[1] == "pipeline" then
                    return vim.tbl_filter(function(item)
                        return vim.startswith(item, ArgLead)
                    end, {"set", "unset", "info"})
                elseif args[1] == "build" then
                    return vim.tbl_filter(function(item)
                        return vim.startswith(item, ArgLead)
                    end, {"current", "list", "open", "refresh", "rebuild"})
                elseif args[1] == "branch" then
                    return vim.tbl_filter(function(item)
                        return vim.startswith(item, ArgLead)
                    end, {"set", "unset", "info"})
                elseif args[1] == "debug" then
                    return vim.tbl_filter(function(item)
                        return vim.startswith(item, ArgLead)
                    end, {"config", "reset"})
                end
            elseif arg_count == 3 then
                if args[1] == "org" and (args[2] == "remove" or args[2] == "switch") then
                    local orgs = config_module.list_organizations()
                    return vim.tbl_filter(function(item)
                        return vim.startswith(item, ArgLead)
                    end, vim.tbl_keys(orgs))
                end
            end
            
            return {}
        end
    })
end

return M