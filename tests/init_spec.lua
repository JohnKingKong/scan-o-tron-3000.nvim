-- tests/init_spec.lua
describe("scan-o-tron-3000.init", function()
  local scan, config

  before_each(function()
    for _, mod in ipairs({
      "scan-o-tron-3000",
      "scan-o-tron-3000.config",
      "scan-o-tron-3000.positions",
      "scan-o-tron-3000.runner",
      "scan-o-tron-3000.panel",
    }) do
      package.loaded[mod] = nil
    end
    scan = require("scan-o-tron-3000")
    config = require("scan-o-tron-3000.config")
  end)

  it("setup() forwards options to config", function()
    local fake_adapter = { name = "fake" }
    scan.setup({ adapters = { fake_adapter } })
    assert.are.same({ fake_adapter }, config.get().adapters)
  end)

  it("run_nearest() notifies when no adapter matches the current buffer", function()
    scan.setup({ adapters = {} })
    vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(false, true))
    vim.bo.filetype = "text"

    local notified
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      notified = { msg = msg, level = level }
    end

    scan.run_nearest()

    vim.notify = original_notify
    assert.is_not_nil(notified)
    assert.are.equal(vim.log.levels.WARN, notified.level)
  end)

  it("toggle_panel() delegates to panel.toggle()", function()
    local panel = require("scan-o-tron-3000.panel")
    local called = false
    panel.toggle = function()
      called = true
    end

    scan.toggle_panel()
    assert.is_true(called)
  end)

  it("run_nearest() resolves the innermost test under the cursor and passes kind='test' to build_command", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/tmp/fake.spec.ts")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3", "line4" })
    vim.api.nvim_set_current_buf(bufnr)

    local captured_scope
    local fake_adapter = {
      name = "fake",
      is_test_file = function(path)
        return path:match("%.spec%.ts$") ~= nil
      end,
      treesitter_query = function()
        return {
          { type = "describe", name = "outer", range = { 0, 0, 3, 0 } },
          { type = "test", name = "inner test", range = { 1, 0, 2, 0 } },
        }
      end,
      build_command = function(scope)
        captured_scope = scope
        return { "fake-cmd" }
      end,
      parse_results = function()
        return {}
      end,
    }

    scan.setup({ adapters = { fake_adapter } })
    vim.api.nvim_win_set_cursor(0, { 2, 0 }) -- row index 1 (0-based), inside "inner test"'s range

    local original_system = vim.system
    -- Stub out the real process spawn; build_command runs synchronously before
    -- system_fn is invoked, so we never need the callback to fire.
    vim.system = function(_, _, _)
      return { pid = 1 }
    end

    scan.run_nearest()

    vim.system = original_system

    assert.is_not_nil(captured_scope)
    assert.are.equal("test", captured_scope.kind)
    assert.are.equal("inner test", captured_scope.position.name)
  end)

  it("run_nearest() resolves an enclosing describe as kind='suite' outside a nested test", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/tmp/fake2.spec.ts")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3", "line4" })
    vim.api.nvim_set_current_buf(bufnr)

    local captured_scope
    local fake_adapter = {
      name = "fake",
      is_test_file = function(path)
        return path:match("%.spec%.ts$") ~= nil
      end,
      treesitter_query = function()
        return {
          { type = "describe", name = "outer", range = { 0, 0, 3, 0 } },
          { type = "test", name = "inner test", range = { 1, 0, 2, 0 } },
        }
      end,
      build_command = function(scope)
        captured_scope = scope
        return { "fake-cmd" }
      end,
      parse_results = function()
        return {}
      end,
    }

    scan.setup({ adapters = { fake_adapter } })
    -- Row index 3 (0-based) is inside "outer"'s range (0-3) but outside "inner test"'s range (1-2).
    vim.api.nvim_win_set_cursor(0, { 4, 0 })

    local original_system = vim.system
    vim.system = function(_, _, _)
      return { pid = 1 }
    end

    scan.run_nearest()

    vim.system = original_system

    assert.is_not_nil(captured_scope)
    assert.are.equal("suite", captured_scope.kind)
    assert.are.equal("outer", captured_scope.position.name)
  end)
end)
