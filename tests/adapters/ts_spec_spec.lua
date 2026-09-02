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

    it("returns nil instead of throwing on a malformed package.json", function()
      assert.is_nil(ts_spec.detect_framework("tests/fixtures/package-malformed.json"))
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
      assert.are.same({ "npx", "mocha", "--reporter", "json", "src/foo.spec.ts", "--grep", "does the thing" }, cmd)
    end)

    it("escapes regex metacharacters in the test name for -t (e.g. RxJS-style '$' suffixes)", function()
      local cmd = ts_spec.build_command({
        kind = "test",
        path = "src/foo.spec.ts",
        position = { name = "onMessageUpdated$ emits" },
        package_json_path = "tests/fixtures/package-jest.json",
      })
      assert.are.same({ "npx", "jest", "--json", "src/foo.spec.ts", "-t", "onMessageUpdated\\$ emits" }, cmd)
    end)

    it("escapes regex metacharacters in the test name for --grep", function()
      local cmd = ts_spec.build_command({
        kind = "test",
        path = "src/foo.spec.ts",
        position = { name = "does the (thing) [again]" },
        package_json_path = "tests/fixtures/package-mocha.json",
      })
      assert.are.same(
        { "npx", "mocha", "--reporter", "json", "src/foo.spec.ts", "--grep", "does the \\(thing\\) \\[again\\]" },
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

    it("treats a mocha test with a JSON null err as a pass, not a crash", function()
      local stdout = '{"tests":[{"title":"passes","fullTitle":"outer passes","err":null}]}'

      local parsed = ts_spec.parse_results(stdout)
      assert.are.equal("pass", parsed["passes"].status)
      assert.is_nil(parsed["passes"].message)
    end)

    it("also groups jest/vitest results by file, for project-wide runs spanning multiple files", function()
      local stdout = vim.json.encode({
        testResults = {
          {
            name = "/repo/a.spec.ts",
            assertionResults = {
              { ancestorTitles = {}, title = "a passes", status = "passed" },
            },
          },
          {
            name = "/repo/b.spec.ts",
            assertionResults = {
              { ancestorTitles = {}, title = "b fails", status = "failed", failureMessages = { "boom" } },
            },
          },
        },
      })

      local by_name, by_file = ts_spec.parse_results(stdout)
      assert.are.equal("pass", by_name["a passes"].status)
      assert.are.equal("fail", by_name["b fails"].status)

      assert.are.equal("pass", by_file["/repo/a.spec.ts"]["a passes"].status)
      assert.are.equal("fail", by_file["/repo/b.spec.ts"]["b fails"].status)
      assert.are.equal("boom", by_file["/repo/b.spec.ts"]["b fails"].message)
      assert.is_nil(by_file["/repo/a.spec.ts"]["b fails"])
    end)

    it("also groups mocha results by each test's `file` field", function()
      local stdout = vim.json.encode({
        tests = {
          { title = "a passes", fullTitle = "a passes", file = "/repo/a.spec.ts", err = vim.empty_dict() },
          {
            title = "b fails",
            fullTitle = "b fails",
            file = "/repo/b.spec.ts",
            err = { message = "boom" },
          },
        },
      })

      local by_name, by_file = ts_spec.parse_results(stdout)
      assert.are.equal("pass", by_name["a passes"].status)
      assert.are.equal("fail", by_name["b fails"].status)

      assert.are.equal("pass", by_file["/repo/a.spec.ts"]["a passes"].status)
      assert.are.equal("fail", by_file["/repo/b.spec.ts"]["b fails"].status)
    end)
  end)
end)
