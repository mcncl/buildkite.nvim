local M = {}

-- Check if current directory is a git repository
function M.is_git_repo(cwd)
    cwd = cwd or vim.fn.getcwd()
    local git_dir = vim.fn.finddir('.git', cwd .. ';')
    return git_dir ~= ''
end

-- Get current git branch name
function M.get_current_branch(cwd)
    if not M.is_git_repo(cwd) then
        return nil
    end
    
    local cmd = string.format('cd %s && git branch --show-current', vim.fn.shellescape(cwd or vim.fn.getcwd()))
    local handle = io.popen(cmd)
    if not handle then
        return nil
    end
    
    local result = handle:read("*a")
    handle:close()
    
    if result then
        return vim.trim(result)
    end
    
    return nil
end

-- Get git remote URL
function M.get_remote_url(remote_name, cwd)
    remote_name = remote_name or 'origin'
    
    if not M.is_git_repo(cwd) then
        return nil
    end
    
    local cmd = string.format('cd %s && git remote get-url %s', 
        vim.fn.shellescape(cwd or vim.fn.getcwd()), 
        vim.fn.shellescape(remote_name))
    local handle = io.popen(cmd)
    if not handle then
        return nil
    end
    
    local result = handle:read("*a")
    handle:close()
    
    if result then
        return vim.trim(result)
    end
    
    return nil
end

-- Get current commit hash
function M.get_current_commit(cwd)
    if not M.is_git_repo(cwd) then
        return nil
    end
    
    local cmd = string.format('cd %s && git rev-parse HEAD', vim.fn.shellescape(cwd or vim.fn.getcwd()))
    local handle = io.popen(cmd)
    if not handle then
        return nil
    end
    
    local result = handle:read("*a")
    handle:close()
    
    if result then
        return vim.trim(result)
    end
    
    return nil
end

-- Get short commit hash
function M.get_current_commit_short(cwd)
    if not M.is_git_repo(cwd) then
        return nil
    end
    
    local cmd = string.format('cd %s && git rev-parse --short HEAD', vim.fn.shellescape(cwd or vim.fn.getcwd()))
    local handle = io.popen(cmd)
    if not handle then
        return nil
    end
    
    local result = handle:read("*a")
    handle:close()
    
    if result then
        return vim.trim(result)
    end
    
    return nil
end

-- Extract repository name from remote URL
function M.get_repo_name_from_url(url)
    if not url then
        return nil
    end
    
    -- Handle both SSH and HTTPS URLs
    local patterns = {
        "git@[^:]+:(.+)%.git$",  -- SSH: git@github.com:user/repo.git
        "git@[^:]+:(.+)$",       -- SSH without .git: git@github.com:user/repo
        "https?://[^/]+/(.+)%.git$", -- HTTPS: https://github.com/user/repo.git
        "https?://[^/]+/(.+)$",      -- HTTPS without .git: https://github.com/user/repo
    }
    
    for _, pattern in ipairs(patterns) do
        local match = url:match(pattern)
        if match then
            return match
        end
    end
    
    return nil
end

-- Get repository name for current directory
function M.get_repo_name(cwd)
    local remote_url = M.get_remote_url('origin', cwd)
    if not remote_url then
        return nil
    end
    
    return M.get_repo_name_from_url(remote_url)
end

-- Get git repository root directory
function M.get_repo_root(cwd)
    if not M.is_git_repo(cwd) then
        return nil
    end
    
    local cmd = string.format('cd %s && git rev-parse --show-toplevel', vim.fn.shellescape(cwd or vim.fn.getcwd()))
    local handle = io.popen(cmd)
    if not handle then
        return nil
    end
    
    local result = handle:read("*a")
    handle:close()
    
    if result then
        return vim.trim(result)
    end
    
    return nil
end

-- Check if there are uncommitted changes
function M.has_uncommitted_changes(cwd)
    if not M.is_git_repo(cwd) then
        return false
    end
    
    local cmd = string.format('cd %s && git status --porcelain', vim.fn.shellescape(cwd or vim.fn.getcwd()))
    local handle = io.popen(cmd)
    if not handle then
        return false
    end
    
    local result = handle:read("*a")
    handle:close()
    
    return result and vim.trim(result) ~= ""
end

-- Get list of changed files
function M.get_changed_files(cwd)
    if not M.is_git_repo(cwd) then
        return {}
    end
    
    local cmd = string.format('cd %s && git status --porcelain', vim.fn.shellescape(cwd or vim.fn.getcwd()))
    local handle = io.popen(cmd)
    if not handle then
        return {}
    end
    
    local result = handle:read("*a")
    handle:close()
    
    if not result or result == "" then
        return {}
    end
    
    local files = {}
    for line in result:gmatch("[^\r\n]+") do
        local status = line:sub(1, 2)
        local file = line:sub(4)
        table.insert(files, {
            status = status,
            file = file,
        })
    end
    
    return files
end

return M