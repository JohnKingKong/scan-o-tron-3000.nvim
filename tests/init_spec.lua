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
end)
