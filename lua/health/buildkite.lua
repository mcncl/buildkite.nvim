-- Health check for buildkite.nvim
local M = {}

-- Re-export the check function from buildkite.health
function M.check()
  -- Forward to the existing health check implementation
  require('buildkite.health').check()
end

return M
