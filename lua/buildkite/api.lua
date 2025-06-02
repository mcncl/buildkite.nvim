local curl = require("plenary.curl")
local config_module = require("buildkite.config")

local M = {}
local global_config = nil

function M.setup(user_config)
    global_config = config_module.setup(user_config)
    return global_config
end

function M.get_config()
    if not global_config then
        global_config = config_module.get_config()
    end
    return global_config
end

function M.request(org_name, endpoint, opts)
    opts = opts or {}
    
    local config = M.get_config()
    
    -- Use current organization if none specified
    if not org_name then
        org_name = config_module.get_current_organization()
        if not org_name then
            error("No current organization set. Use :Buildkite org add or :Buildkite org switch")
        end
    end
    
    local org_config = config.organizations[org_name]
    
    if not org_config then
        error(string.format("Organization '%s' not configured", org_name))
    end
    
    if not org_config.token then
        error(string.format("No API token configured for organization '%s'", org_name))
    end
    
    local url = config.api.endpoint .. endpoint
    
    local headers = {
        Authorization = "Bearer " .. org_config.token,
        ["Content-Type"] = "application/json",
    }
    
    -- Add query parameters if provided
    if opts.params then
        local params = {}
        for key, value in pairs(opts.params) do
            table.insert(params, key .. "=" .. vim.uri_encode(tostring(value)))
        end
        if #params > 0 then
            url = url .. "?" .. table.concat(params, "&")
        end
    end
    
    local response = curl.get(url, {
        headers = headers,
        timeout = config.api.timeout
    })
    
    if response.status ~= 200 then
        error(string.format("API request failed with status %d: %s", 
            response.status, response.body))
    end
    
    -- Use vim's JSON decode since plenary.json doesn't have encode/decode
    local ok, decoded = pcall(vim.fn.json_decode, response.body)
    if not ok then
        error("Failed to decode JSON response: " .. decoded)
    end
    
    return decoded
end

function M.get_pipelines(org_name)
    org_name = org_name or config_module.get_current_organization()
    return M.request(org_name, "/organizations/" .. org_name .. "/pipelines")
end

function M.get_pipeline(org_name, pipeline_slug)
    org_name = org_name or config_module.get_current_organization()
    return M.request(org_name, "/organizations/" .. org_name .. "/pipelines/" .. pipeline_slug)
end

function M.get_builds(org_name, pipeline_slug, opts)
    opts = opts or {}
    org_name = org_name or config_module.get_current_organization()
    local endpoint = "/organizations/" .. org_name .. "/pipelines/" .. pipeline_slug .. "/builds"
    
    return M.request(org_name, endpoint, {
        params = opts
    })
end

function M.get_builds_for_branch(org_name, pipeline_slug, branch, opts)
    opts = opts or {}
    opts.branch = branch
    org_name = org_name or config_module.get_current_organization()
    
    return M.get_builds(org_name, pipeline_slug, opts)
end

function M.get_latest_build_for_branch(org_name, pipeline_slug, branch)
    org_name = org_name or config_module.get_current_organization()
    local builds = M.get_builds_for_branch(org_name, pipeline_slug, branch, {
        per_page = 1,
        page = 1
    })
    
    if builds and #builds > 0 then
        return builds[1]
    end
    
    return nil
end

function M.get_build(org_name, pipeline_slug, build_number)
    org_name = org_name or config_module.get_current_organization()
    local endpoint = "/organizations/" .. org_name .. "/pipelines/" .. pipeline_slug .. "/builds/" .. build_number
    return M.request(org_name, endpoint)
end

function M.get_build_jobs(org_name, pipeline_slug, build_number)
    org_name = org_name or config_module.get_current_organization()
    local endpoint = "/organizations/" .. org_name .. "/pipelines/" .. pipeline_slug .. "/builds/" .. build_number .. "/jobs"
    return M.request(org_name, endpoint)
end

function M.get_latest_builds_for_org(org_name, opts)
    opts = opts or {}
    org_name = org_name or config_module.get_current_organization()
    
    local pipelines = M.get_pipelines(org_name)
    local config = M.get_config()
    local org_config = config.organizations[org_name]
    
    local filtered_pipelines = pipelines
    if org_config.repositories and #org_config.repositories > 0 then
        filtered_pipelines = {}
        for _, pipeline in ipairs(pipelines) do
            for _, repo in ipairs(org_config.repositories) do
                if pipeline.slug == repo or pipeline.name == repo or 
                   (pipeline.repository and pipeline.repository.name == repo) then
                    table.insert(filtered_pipelines, pipeline)
                    break
                end
            end
        end
    end
    
    local results = {}
    
    for _, pipeline in ipairs(filtered_pipelines) do
        local build_opts = {
            per_page = opts.per_page or 1,
            page = 1
        }
        
        if opts.branch then
            build_opts.branch = opts.branch
        end
        
        local builds = M.get_builds(org_name, pipeline.slug, build_opts)
        if builds and #builds > 0 then
            table.insert(results, {
                pipeline = pipeline,
                latest_build = builds[1]
            })
        end
    end
    
    return results
end

function M.get_current_project_build(cwd, branch)
    local config = M.get_config()
    local org_name, pipeline_slug = config_module.get_project_pipeline(cwd)
    
    if not org_name or not pipeline_slug then
        return nil, "No pipeline configured for current project"
    end
    
    if not branch then
        local git = require("buildkite.git")
        branch = git.get_current_branch(cwd)
        if not branch then
            return nil, "Could not determine current git branch"
        end
    end
    
    local build = M.get_latest_build_for_branch(org_name, pipeline_slug, branch)
    return build, nil
end



function M.rebuild(org_name, pipeline_slug, build_number)
    org_name = org_name or config_module.get_current_organization()
    local endpoint = "/organizations/" .. org_name .. "/pipelines/" .. pipeline_slug .. "/builds/" .. build_number .. "/rebuild"
    
    local config = M.get_config()
    local org_config = config.organizations[org_name]
    
    if not org_config then
        error(string.format("Organization '%s' not configured", org_name))
    end
    
    local url = config.api.endpoint .. endpoint
    local headers = {
        Authorization = "Bearer " .. org_config.token,
        ["Content-Type"] = "application/json",
    }
    
    local response = curl.put(url, {
        headers = headers,
        timeout = config.api.timeout
    })
    
    if response.status ~= 200 then
        error(string.format("Failed to rebuild: %d %s", response.status, response.body))
    end
    
    local ok, decoded = pcall(vim.fn.json_decode, response.body)
    if not ok then
        error("Failed to decode JSON response: " .. decoded)
    end
    
    return decoded
end

return M