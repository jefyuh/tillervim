local ok, err = xpcall(function()
  -- A separate personal repository uses native Neovim files and lazy specs.
  local api = vim.api
  local root = assert(vim.env.TILLERVIM_TEST_ROOT)
  local tmp = assert(vim.uv.fs_realpath(vim.env.KEY_TEST_TMP))
  local user = tmp .. "/config"
  vim.fn.mkdir(user .. "/lua/config", "p")
  vim.fn.mkdir(user .. "/lua/plugins", "p")
  vim.fn.writefile({ 'vim.opt.tabstop = 3', 'vim.g.tillervim_options_loaded = true' }, user .. "/lua/config/options.lua")
  vim.fn.writefile({
    'assert(vim.fn.maparg("<leader>uw", "n") ~= "", "defaults must precede user mappings")',
    'vim.keymap.del("n", "<leader>uw")',
    'vim.keymap.set("n", "<leader>uW", function() vim.wo.wrap = not vim.wo.wrap end, { desc = "Toggle word wrap" })',
    'vim.keymap.del("n", "<leader>us")',
  }, user .. "/lua/config/keymaps.lua")
  vim.fn.writefile({ 'vim.g.tillervim_autocmds_loaded = true' }, user .. "/lua/config/autocmds.lua")
  vim.fn.writefile({
    'return {',
    '  { "folke/which-key.nvim", enabled = false },',
    '  { "stevearc/oil.nvim", opts = { keymaps = {',
    '    ["<C-v>"] = false, ["<C-s>"] = false, ["<M-p>"] = false,',
    '    ["<C-y>"] = { "actions.select", opts = { vertical = true }, mode = "n", desc = "Open in vertical split" },',
    '  } } },',
    '  { "stevearc/aerial.nvim", opts = { keymaps = {',
    '    ["<C-v>"] = false, ["<C-s>"] = false,',
    '    ["<C-y>"] = { callback = function() require("aerial").select({ split = "v" }) end, desc = "Open in vertical split" },',
    '  } } },',
    '  { "folke/snacks.nvim", opts = { picker = { win = { input = { keys = {',
    '    ["<c-v>"] = false, ["<c-s>"] = false, ["<M-p>"] = false,',
    '    ["<C-y>"] = { "edit_vsplit", mode = { "n", "i" }, desc = "Open in vertical split" },',
    '  } } } } } },',
    '  { "milanglacier/minuet-ai.nvim", opts = { debounce = 321, virtualtext = { keymap = { accept = "<C-o>" } } } },',
    '  { "git-review.nvim", opts = { history_limit = 17, max_file_size = 123456 } },',
    '  { "monaqa/dial.nvim", keys = function(_, keys)',
    '    for _, key in ipairs(keys) do if key[1] == "<C-a>" then key[1] = "<M-a>" end end',
    '    return keys',
    '  end },',
    '  { "agent-workbench.nvim", opts = function(_, opts)',
    '    assert(vim.g.tillervim_options_loaded, "user options must precede Agent setup")',
    '    opts.panel.width = 73',
    '  end, keys = function(_, keys)',
    '    for _, key in ipairs(keys) do if key[1] == "<leader>ae" then key[1] = "<leader>aE" end end',
    '    return keys',
    '  end },',
    '}',
  }, user .. "/lua/plugins/init.lua")
  vim.g.tillervim_config_root = user
  vim.opt.rtp:prepend(root)
  vim.opt.rtp:prepend(user)
  vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")
  vim.go.loadplugins = true
  require("lazy").setup({
    spec = { { dir = root, name = "tillervim", import = "tillervim.plugins" }, { import = "plugins" } },
    defaults = { lazy = true, version = false }, rocks = { enabled = false },
    install = { missing = false }, checker = { enabled = false },
    lockfile = user .. "/lazy-lock.json", performance = { rtp = { reset = false } },
  })
  vim.o.columns, vim.o.lines = 180, 45
  local function check(value, why) assert(value, why) end
  local function local_map(buf, key, mode)
    return api.nvim_buf_call(buf, function() return vim.fn.maparg(key, mode or 'n', false, true) end)
  end
  check(package.loaded['which-key'] == nil, 'which-key is absent')
  check(vim.fn.maparg('ss', 'n') ~= '', 'editor actions exist without which-key')
  check(vim.fn.maparg(',x', 'n') ~= '' and vim.fn.maparg('sd', 'n') ~= '',
    'omitted core/action choices retain their plugin defaults')
  check(vim.fn.maparg('<leader>uW', 'n') ~= '' and vim.fn.maparg('<leader>uw', 'n') == '',
    'an action remap installs only its chosen key')
  check(vim.fn.maparg('<leader>us', 'n') == '', 'false disables an action')
  local file = tmp .. '/entry.lua'
  vim.fn.writefile({ 'local function entry() end', 'entry()' }, file)
  require('oil').open(tmp)
  local oil_buf = api.nvim_get_current_buf()
  local row
  check(vim.wait(2000, function()
    for i = 1, api.nvim_buf_line_count(oil_buf) do
      local entry = require('oil').get_entry_on_line(oil_buf, i)
      if entry and entry.name == 'entry.lua' then row = i; return true end
    end
  end, 10), 'real Oil fixture appears')
  check(local_map(oil_buf, '<C-y>').desc == 'Open in vertical split', 'Oil uses the shared key/description')
  check(local_map(oil_buf, '<C-v>').buffer ~= 1 and local_map(oil_buf, '<C-s>').buffer ~= 1,
  'Oil removes both replaced and disabled defaults')
  check(local_map(oil_buf, '<M-p>').buffer ~= 1 and local_map(oil_buf, '<C-y>', 'x').buffer ~= 1,
  'disabled preview and Visual mode remain free')
  api.nvim_win_set_cursor(0, { row, 0 })
  local_map(oil_buf, '<C-y>').callback()
  check(vim.wait(2000, function() return api.nvim_buf_get_name(0) == file end, 10), 'Oil shared key opens the actual file')
  check(vim.fn.winlayout()[1] == 'row', 'Oil opens a vertical split')
  local picker = Snacks.picker({ items = { { text = 'entry.lua', file = file } }, format = 'file' })
  check(vim.wait(2000, function() return picker.list:count() == 1 end, 10), 'real picker has the fixture')
  local input = picker.input.win.buf
  check(local_map(input, '<C-y>').buffer == 1 and local_map(input, '<C-y>', 'i').buffer == 1,
  'picker applies the shared key in Normal and Insert')
  check(local_map(input, '<C-v>').buffer ~= 1 and local_map(input, '<C-s>').buffer ~= 1,
  'picker old defaults are gone')
  api.nvim_set_current_win(picker.input.win.win)
  vim.cmd.stopinsert()
  api.nvim_feedkeys(vim.keycode('<C-y>'), 'xt', false)
  check(vim.wait(2000, function() return picker.closed and api.nvim_buf_get_name(0) == file end, 10),
  'picker shared key opens the actual file')
  vim.cmd.AerialOpen()
  local aerial_buf
  check(vim.wait(3000, function()
    for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
      local buf = api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == 'aerial' then aerial_buf = buf; return true end
    end
  end, 10), 'real Aerial opens')
  check(local_map(aerial_buf, '<C-y>').desc == 'Open in vertical split', 'Aerial translates the same shared action')
  check(local_map(aerial_buf, '<C-v>').buffer ~= 1 and local_map(aerial_buf, '<C-s>').buffer ~= 1,
  'Aerial removes replaced and disabled defaults')
  vim.cmd.AerialClose()
  require('editor_core.keyguide').show()
  local guide = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  check(guide:find('uW', 1, true) and guide:find('Toggle word wrap', 1, true), 'guide reads actual user maps')
  check(not guide:find('Shared open actions', 1, true), 'guide requires no semantic key registry')
  check(package.loaded['which-key'] == nil, 'no which-key loaded while exercising actual actions')
  vim.cmd.close()
  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'true' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  api.nvim_feedkeys(vim.keycode('<M-a>'), 'xt', false)
  check(api.nvim_get_current_line() == 'false', 'Dial native keys override preserves its callback')
  check(vim.fn.maparg('<C-a>', 'n') == '' and vim.fn.maparg('<C-a>', 'x') == '', 'Dial old modes are removed')
  check(vim.fn.maparg('<leader>ae', 'n') == '', 'inline remap removes old key')
  local inline = vim.fn.maparg('<leader>aE', 'n', false, true)
  local state = require('agent_workbench.state')
  state._set_providers({ { name = 'work', label = 'Work', api = { adapter = 'openai', api_key = '$SPEC_WORK_KEY', label = 'Personal billing' } } })
  vim.api.nvim_exec_autocmds('User', { pattern = 'AIStateChanged', modeline = false })
  local relabelled = vim.fn.maparg('<leader>aE', 'n', false, true)
  check(relabelled.callback == inline.callback and relabelled.expr == 1, 'billing relabel retains user mapping behavior')
  check(relabelled.desc:find('Personal billing', 1, true) and vim.fn.maparg('<leader>ae', 'n') == '', 'billing switch relabels remap without resurrecting old key')
  require('lazy').load({ plugins = { 'minuet-ai.nvim', 'git-review.nvim' } })
  check(require('minuet').config.debounce == 321 and require('minuet').config.virtualtext.keymap.accept == '<C-o>', 'Minuet receives native user opts')
  check(require('git_review').options().history_limit == 17 and require('git_review').options().max_file_size == 123456, 'Git overrides are not replaced by distribution defaults')
  check(not require('llama_service').ready(), 'headless native overrides load no model')
  vim.fn.writefile({ 'user-config-complete' }, tmp .. '/result')
  vim.cmd('qa!')

end, debug.traceback)
if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") end
