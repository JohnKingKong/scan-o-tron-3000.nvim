describe("scan-o-tron-3000.config", function()
  local config

  before_each(function()
    package.loaded["scan-o-tron-3000.config"] = nil
    config = require("scan-o-tron-3000.config")
  end)

  it("defaults to the ts-spec adapter when setup() is called with no adapters key", function()
    config.setup()
    local names = {}
    for _, adapter in ipairs(config.get().adapters) do
      table.insert(names, adapter.name)
    end
    assert.is_true(vim.tbl_contains(names, "ts-spec"))
  end)

  it("stores adapters passed to setup()", function()
    local fake_adapter = { name = "fake" }
    config.setup({ adapters = { fake_adapter } })
    assert.are.same({ fake_adapter }, config.get().adapters)
  end)

  it("registers the ts-spec adapter by default when setup() is never called", function()
    local names = {}
    for _, adapter in ipairs(config.get().adapters) do
      table.insert(names, adapter.name)
    end
    assert.is_true(vim.tbl_contains(names, "ts-spec"))
  end)
end)
