-- tests/adapters/ts_spec_spec.lua
describe("scan-o-tron-3000.adapters.ts-spec", function()
  local ts_spec

  before_each(function()
    package.loaded["scan-o-tron-3000.adapters.ts-spec"] = nil
    ts_spec = require("scan-o-tron-3000.adapters.ts-spec")
  end)

  describe("is_test_file", function()
    it("matches .spec.ts files", function()
      assert.is_true(ts_spec.is_test_file("/project/src/foo.spec.ts"))
    end)

    it("matches .test.ts files", function()
      assert.is_true(ts_spec.is_test_file("/project/src/foo.test.ts"))
    end)

    it("does not match plain .ts files", function()
      assert.is_false(ts_spec.is_test_file("/project/src/foo.ts"))
    end)
  end)

  describe("treesitter_query", function()
    it("discovers describe/it/test nodes in a real fixture buffer", function()
      local bufnr = vim.fn.bufadd("tests/fixtures/example.spec.ts")
      vim.fn.bufload(bufnr)
      vim.bo[bufnr].filetype = "typescript"

      local flat = ts_spec.treesitter_query(bufnr)

      local names = {}
      for _, pos in ipairs(flat) do
        table.insert(names, pos.type .. ":" .. pos.name)
      end

      assert.is_true(vim.tbl_contains(names, "describe:outer"))
      assert.is_true(vim.tbl_contains(names, "test:does the first thing"))
      assert.is_true(vim.tbl_contains(names, "describe:inner"))
      assert.is_true(vim.tbl_contains(names, "test:does the second thing"))
      assert.is_true(vim.tbl_contains(names, "test:a bare test call"))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("detect_framework", function()
    it("detects vitest", function()
      assert.are.equal("vitest", ts_spec.detect_framework("tests/fixtures/package-vitest.json"))
    end)

    it("detects jest", function()
      assert.are.equal("jest", ts_spec.detect_framework("tests/fixtures/package-jest.json"))
    end)

    it("detects mocha", function()
      assert.are.equal("mocha", ts_spec.detect_framework("tests/fixtures/package-mocha.json"))
    end)
  end)

  describe("build_command", function()
    it("builds a project-wide vitest command", function()
      local cmd = ts_spec.build_command({ kind = "project", package_json_path = "tests/fixtures/package-vitest.json" })
      assert.are.same({ "npx", "vitest", "run", "--reporter=json" }, cmd)
    end)

    it("builds a file-scoped jest command", function()
      local cmd = ts_spec.build_command({
        kind = "file",
        path = "src/foo.spec.ts",
        package_json_path = "tests/fixtures/package-jest.json",
      })
      assert.are.same({ "npx", "jest", "--json", "src/foo.spec.ts" }, cmd)
    end)

    it("builds a test-scoped mocha command using --grep", function()
      local cmd = ts_spec.build_command({
        kind = "test",
        path = "src/foo.spec.ts",
        position = { name = "does the thing" },
        package_json_path = "tests/fixtures/package-mocha.json",
      })
      assert.are.same(
        { "npx", "mocha", "--reporter", "json", "src/foo.spec.ts", "--grep", "does the thing" },
        cmd
      )
    end)
  end)

  describe("parse_results", function()
    it("parses jest/vitest-shaped JSON output", function()
      local stdout = vim.json.encode({
        testResults = {
          {
            assertionResults = {
              { ancestorTitles = { "outer" }, title = "passes", status = "passed" },
              {
                ancestorTitles = { "outer" },
                title = "fails",
                status = "failed",
                failureMessages = { "expected 1 to be 2" },
              },
              { ancestorTitles = { "outer" }, title = "skipped", status = "pending" },
            },
          },
        },
      })

      local parsed = ts_spec.parse_results(stdout)
      assert.are.equal("pass", parsed["passes"].status)
      assert.are.equal("fail", parsed["fails"].status)
      assert.are.equal("expected 1 to be 2", parsed["fails"].message)
      assert.are.equal("skip", parsed["skipped"].status)
    end)

    it("parses mocha-shaped JSON output", function()
      local stdout = vim.json.encode({
        tests = {
          { title = "passes", fullTitle = "outer passes", err = vim.empty_dict() },
          { title = "fails", fullTitle = "outer fails", err = { message = "expected 1 to be 2" } },
        },
      })

      local parsed = ts_spec.parse_results(stdout)
      assert.are.equal("pass", parsed["passes"].status)
      assert.are.equal("fail", parsed["fails"].status)
      assert.are.equal("expected 1 to be 2", parsed["fails"].message)
    end)
  end)
end)
