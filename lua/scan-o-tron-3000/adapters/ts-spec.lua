-- lua/scan-o-tron-3000/adapters/ts-spec.lua
local M = {}

M.name = "ts-spec"
M.filetypes = { "typescript", "typescriptreact" }

function M.is_test_file(path)
  return path:match("%.spec%.tsx?$") ~= nil or path:match("%.test%.tsx?$") ~= nil
end

local QUERY = [[
(call_expression
  function: (identifier) @_fn (#eq? @_fn "describe")
  arguments: (arguments
    (string (string_fragment) @describe.name)
    [(arrow_function) (function_expression)])) @describe.definition

(call_expression
  function: (identifier) @_fn (#any-of? @_fn "it" "test")
  arguments: (arguments
    (string (string_fragment) @test.name)
    [(arrow_function) (function_expression)])) @test.definition
]]

-- .tsx files need the separate "tsx" tree-sitter grammar, not "typescript" --
-- the plain typescript grammar doesn't understand JSX and produces a parse
-- tree with errors on real .tsx content (tree-sitter's error recovery can
-- paper over this for some files, silently corrupt describe/it discovery on
-- others, so this can't be left to luck).
local LANGUAGE_FOR_FILETYPE = {
  typescript = "typescript",
  typescriptreact = "tsx",
}

function M.treesitter_query(bufnr)
  local lang = LANGUAGE_FOR_FILETYPE[vim.bo[bufnr].filetype] or "typescript"
  local parser = vim.treesitter.get_parser(bufnr, lang)
  local tree = parser:parse()[1]
  local root = tree:root()
  local query = vim.treesitter.query.parse(lang, QUERY)

  local flat = {}
  for _, match, _ in query:iter_matches(root, bufnr, 0, -1, { all = true }) do
    local entry = { type = nil, name = nil, range = nil }
    for id, nodes in pairs(match) do
      local capture_name = query.captures[id]
      for _, node in ipairs(nodes) do
        if capture_name == "describe.definition" then
          entry.type = "describe"
          entry.range = { node:range() }
        elseif capture_name == "test.definition" then
          entry.type = "test"
          entry.range = { node:range() }
        elseif capture_name == "describe.name" or capture_name == "test.name" then
          entry.name = vim.treesitter.get_node_text(node, bufnr)
        end
      end
    end
    if entry.type and entry.range then
      table.insert(flat, entry)
    end
  end

  table.sort(flat, function(a, b)
    if a.range[1] ~= b.range[1] then
      return a.range[1] < b.range[1]
    end
    return a.range[2] < b.range[2]
  end)

  return flat
end

function M.detect_framework(package_json_path)
  local ok, contents = pcall(vim.fn.readfile, package_json_path)
  if not ok then
    return nil
  end
  local decode_ok, decoded = pcall(vim.json.decode, table.concat(contents, "\n"))
  if not decode_ok then
    return nil
  end
  local deps = vim.tbl_extend("force", decoded.dependencies or {}, decoded.devDependencies or {})

  if deps.vitest then
    return "vitest"
  elseif deps.jest then
    return "jest"
  elseif deps.mocha then
    return "mocha"
  end
  return nil
end

-- Both jest/vitest's -t and mocha's --grep treat their argument as a regex.
-- Test names routinely contain regex metacharacters (this codebase's RxJS
-- naming convention alone produces titles like "onMessageUpdated$ emits"),
-- so the name is escaped here to match literally instead of as a pattern.
local function escape_regex(name)
  return (name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?{}|\\]", "\\%0"))
end

local function append_scope_args(cmd, framework, scope)
  if scope.kind == "project" then
    return cmd
  end

  table.insert(cmd, scope.path)

  if scope.kind == "file" then
    return cmd
  end

  -- "test" or "suite" scope: filter by name
  local pattern = escape_regex(scope.position.name)
  if framework == "vitest" or framework == "jest" then
    table.insert(cmd, "-t")
    table.insert(cmd, pattern)
  elseif framework == "mocha" then
    table.insert(cmd, "--grep")
    table.insert(cmd, pattern)
  end
  return cmd
end

function M.build_command(scope)
  local framework = M.detect_framework(scope.package_json_path)
  if not framework then
    error("scan-o-tron-3000: could not detect vitest/jest/mocha from " .. scope.package_json_path)
  end

  local cmd
  if framework == "vitest" then
    cmd = { "npx", "vitest", "run", "--reporter=json" }
  elseif framework == "jest" then
    cmd = { "npx", "jest", "--json" }
  else
    cmd = { "npx", "mocha", "--reporter", "json" }
  end

  return append_scope_args(cmd, framework, scope)
end

local STATUS_MAP = { passed = "pass", failed = "fail", pending = "skip", skipped = "skip" }

-- Returns two values: `by_name` (flat, single-namespace map used for the
-- current file's own scoped run -- the long-standing name-only-matching
-- limitation applies here) and `by_file` (the same entries additionally
-- grouped by the file path each framework's JSON reporter attaches to every
-- result), so a project-wide run can populate every tested file's panel
-- entry and gutter marks, not just whichever file happens to be open.
function M.parse_results(stdout)
  local decoded = vim.json.decode(stdout)
  local by_name = {}
  local by_file = {}

  if decoded.testResults then
    -- jest/vitest shape: each entry's `name` is the absolute test file path.
    for _, file_result in ipairs(decoded.testResults) do
      local file_map = {}
      for _, assertion in ipairs(file_result.assertionResults or {}) do
        local entry = {
          status = STATUS_MAP[assertion.status] or "fail",
          message = assertion.failureMessages and assertion.failureMessages[1] or nil,
        }
        by_name[assertion.title] = entry
        file_map[assertion.title] = entry
      end
      if file_result.name then
        by_file[file_result.name] = file_map
      end
    end
  elseif decoded.tests then
    -- mocha shape: each test has `err` populated (non-empty) only on failure,
    -- and carries its own absolute `file` path.
    for _, test in ipairs(decoded.tests) do
      local err = test.err
      if err == vim.NIL then
        err = nil
      end
      local failed = next(err or {}) ~= nil
      local entry = {
        status = failed and "fail" or "pass",
        message = failed and err.message or nil,
      }
      by_name[test.title] = entry
      if test.file then
        by_file[test.file] = by_file[test.file] or {}
        by_file[test.file][test.title] = entry
      end
    end
  end

  return by_name, by_file
end

return M
