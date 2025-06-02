std = "luajit"

globals = {
    "vim",
}

read_globals = {
    -- Neovim globals
    "vim.api",
    "vim.fn",
    "vim.loop",
    "vim.log",
    "vim.notify",
    "vim.tbl_isempty",
    "vim.tbl_keys",
    "vim.tbl_count",
    "vim.tbl_filter",
    "vim.tbl_extend",
    "vim.deepcopy",
    "vim.split",
    "vim.trim",
    "vim.startswith",
    "vim.uri_encode",
    "vim.list_extend",
    "vim.inspect",
    "vim.keymap",
    "vim.ui",
    "vim.health",
    "vim.defer_fn",
    "vim.schedule",
    "vim.v",
    "vim.env",
    "vim.json",
}

ignore = {
    "212", -- Unused argument
    "213", -- Unused loop variable
    "631", -- Line is too long
}

files["lua/buildkite/health.lua"] = {
    ignore = {
        "113", -- Accessing undefined variable (for vim.health compatibility)
    }
}