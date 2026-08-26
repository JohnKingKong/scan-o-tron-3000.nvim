-- tests/scaffold_spec.lua
describe("scan-o-tron-3000 test harness", function()
  it("can require the plugin's root module", function()
    local ok = pcall(require, "scan-o-tron-3000")
    assert.is_true(ok)
  end)
end)
