local M = {}

function M.check()
  local health = vim.health
  local start = health.start or health.report_start
  local report_ok = health.ok or health.report_ok
  local report_warn = health.warn or health.report_warn

  start("scan-o-tron-3000")

  if vim.fn.executable("npx") == 1 then
    report_ok("npx found on $PATH")
  else
    report_warn("npx not found on $PATH — the ts-spec adapter needs it to run vitest/jest/mocha")
  end

  local ok = pcall(vim.treesitter.query.parse, "typescript", "(program) @root")
  if ok then
    report_ok("typescript treesitter parser is installed")
  else
    report_warn("typescript treesitter parser not found — install it via :TSInstall typescript (nvim-treesitter)")
  end
end

return M
