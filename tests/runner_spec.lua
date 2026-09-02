describe("scan-o-tron-3000.runner", function()
  local runner, positions

  before_each(function()
    package.loaded["scan-o-tron-3000.runner"] = nil
    package.loaded["scan-o-tron-3000.positions"] = nil
    runner = require("scan-o-tron-3000.runner")
    positions = require("scan-o-tron-3000.positions")
  end)

  local function make_tree()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "", "", "" })
    local tree = positions.build_tree({ { type = "test", name = "passes", range = { 0, 0, 1, 0 } } })
    tree.bufnr = bufnr
    return tree
  end

  it("marks the scoped node running immediately, then applies results on exit", function()
    local tree = make_tree()
    local adapter = {
      build_command = function()
        return { "fake-cmd" }
      end,
      parse_results = function()
        return { passes = { status = "pass" } }
      end,
    }

    local captured_on_exit
    local fake_system = function(_, _, on_exit)
      captured_on_exit = on_exit
      return { pid = 1 }
    end

    runner.run({
      tree = tree,
      adapter = adapter,
      scope = { kind = "file", path = "x", scope_leaf_names = { "passes" } },
      system_fn = fake_system,
    })

    assert.are.equal("running", tree.children[1].state)

    captured_on_exit({ code = 0, stdout = "{}" })
    assert.are.equal("pass", tree.children[1].state)
  end)

  it("spawns the process with cwd set to the package.json's directory", function()
    local tree = make_tree()
    local adapter = {
      build_command = function()
        return { "fake-cmd" }
      end,
      parse_results = function()
        return {}
      end,
    }

    local captured_opts
    local fake_system = function(_, opts, on_exit)
      captured_opts = opts
      on_exit({ code = 0, stdout = "{}" })
      return { pid = 1 }
    end

    runner.run({
      tree = tree,
      adapter = adapter,
      scope = {
        kind = "file",
        path = "x",
        package_json_path = "/repo/apps/console/package.json",
        scope_leaf_names = { "passes" },
      },
      system_fn = fake_system,
    })

    assert.are.equal("/repo/apps/console", captured_opts.cwd)
  end)

  it("invokes on_complete after applying results", function()
    local tree = make_tree()
    local adapter = {
      build_command = function()
        return { "fake-cmd" }
      end,
      parse_results = function()
        return { passes = { status = "pass" } }
      end,
    }

    local captured_on_exit
    local fake_system = function(_, _, on_exit)
      captured_on_exit = on_exit
      return { pid = 1 }
    end

    local completed = false
    runner.run({
      tree = tree,
      adapter = adapter,
      scope = { kind = "file", path = "x", scope_leaf_names = { "passes" } },
      system_fn = fake_system,
      on_complete = function()
        completed = true
      end,
    })

    assert.is_false(completed)
    captured_on_exit({ code = 0, stdout = "{}" })
    -- signs.render()/on_complete() are deferred via vim.schedule (they touch
    -- buffer/window state, illegal from vim.system's real fast-event
    -- callback), so pump the loop until the scheduled work runs.
    vim.wait(100, function()
      return completed
    end)
    assert.is_true(completed)
  end)

  it("passes the adapter's by-file breakdown through to on_complete", function()
    local tree = make_tree()
    local adapter = {
      build_command = function()
        return { "fake-cmd" }
      end,
      parse_results = function()
        return { passes = { status = "pass" } }, { ["/repo/a.spec.ts"] = { passes = { status = "pass" } } }
      end,
    }

    local captured_on_exit
    local fake_system = function(_, _, on_exit)
      captured_on_exit = on_exit
      return { pid = 1 }
    end

    local captured_by_file
    runner.run({
      tree = tree,
      adapter = adapter,
      scope = { kind = "project", path = "x", scope_leaf_names = { "passes" } },
      system_fn = fake_system,
      on_complete = function(by_file)
        captured_by_file = by_file
      end,
    })

    captured_on_exit({ code = 0, stdout = "{}" })
    vim.wait(100, function()
      return captured_by_file ~= nil
    end)

    assert.is_not_nil(captured_by_file)
    assert.are.equal("pass", captured_by_file["/repo/a.spec.ts"]["passes"].status)
  end)

  it("runs a project-wide scope with no tree at all, without crashing", function()
    local adapter = {
      build_command = function()
        return { "fake-cmd" }
      end,
      parse_results = function()
        return {}, { ["/repo/a.spec.ts"] = { passes = { status = "pass" } } }
      end,
    }

    local captured_on_exit
    local fake_system = function(_, _, on_exit)
      captured_on_exit = on_exit
      return { pid = 1 }
    end

    local captured_by_file
    local ok = pcall(function()
      runner.run({
        tree = nil,
        adapter = adapter,
        scope = { kind = "project", path = "" },
        system_fn = fake_system,
        on_complete = function(by_file)
          captured_by_file = by_file
        end,
      })
    end)
    assert.is_true(ok)

    local exit_ok = pcall(captured_on_exit, { code = 0, stdout = "{}" })
    assert.is_true(exit_ok)

    vim.wait(100, function()
      return captured_by_file ~= nil
    end)

    assert.is_not_nil(captured_by_file)
    assert.are.equal("pass", captured_by_file["/repo/a.spec.ts"]["passes"].status)
  end)

  it("no-ops and notifies when a run is already in flight for the same buffer", function()
    local tree = make_tree()
    local adapter = {
      build_command = function()
        return { "fake-cmd" }
      end,
      parse_results = function()
        return {}
      end,
    }

    local run_count = 0
    local fake_system = function()
      run_count = run_count + 1
      return { pid = 1 }
    end

    local notified
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      notified = { msg = msg, level = level }
    end

    runner.run({
      tree = tree,
      adapter = adapter,
      scope = { kind = "file", path = "x", scope_leaf_names = { "passes" } },
      system_fn = fake_system,
    })
    runner.run({
      tree = tree,
      adapter = adapter,
      scope = { kind = "file", path = "x", scope_leaf_names = { "passes" } },
      system_fn = fake_system,
    })

    vim.notify = original_notify

    assert.are.equal(1, run_count)
    assert.is_not_nil(notified)
    assert.are.equal(vim.log.levels.WARN, notified.level)
  end)

  it("releases the in-flight guard and shows an errored state when system_fn throws synchronously", function()
    local tree = make_tree()
    local adapter = {
      build_command = function()
        return { "fake-cmd" }
      end,
      parse_results = function()
        return {}
      end,
    }

    local fake_system = function()
      error("no such file or directory")
    end

    local notified
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      notified = { msg = msg, level = level }
    end

    runner.run({
      tree = tree,
      adapter = adapter,
      scope = { kind = "file", path = "x", scope_leaf_names = { "passes" } },
      system_fn = fake_system,
    })

    vim.notify = original_notify

    assert.is_false(runner.is_running(tree.bufnr))
    assert.are.equal("errored", tree.children[1].state)
    assert.is_not_nil(notified)
    assert.are.equal(vim.log.levels.ERROR, notified.level)

    local run_count = 0
    local fake_system_2 = function()
      run_count = run_count + 1
      return { pid = 1 }
    end

    runner.run({
      tree = tree,
      adapter = adapter,
      scope = { kind = "file", path = "x", scope_leaf_names = { "passes" } },
      system_fn = fake_system_2,
    })

    assert.are.equal(1, run_count)
  end)
end)
