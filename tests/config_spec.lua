describe("scan-o-tron-3000.config", function()
  local config

  before_each(function()
    package.loaded["scan-o-tron-3000.config"] = nil
    config = require("scan-o-tron-3000.config")
  end)

  it("defaults to an empty setup with no adapters registered yet", function()
    config.setup()
    assert.are.same({}, config.get().adapters)
  end)

  it("stores adapters passed to setup()", function()
    local fake_adapter = { name = "fake" }
    config.setup({ adapters = { fake_adapter } })
    assert.are.same({ fake_adapter }, config.get().adapters)
  end)

  it("get() returns defaults if setup() was never called", function()
    assert.are.same({}, config.get().adapters)
  end)
end)
