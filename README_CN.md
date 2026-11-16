# TillerVim

**以 Agent 为核心的 Neovim 配置。你掌舵，Agent 行动。**

[English](README.md) · [使用手册](docs/MANUAL_CN.md) · [问题排查](docs/DIAGNOSTICS.md)

TillerVim 把编辑、原生 Agent、聊天与 Git Review 放进同一个 Neovim 工作环境。
发行版提供默认组合；个人配置独立维护，使用普通 Lua 和 lazy.nvim spec。

## 包含什么

- **原生 Codex**：内嵌终端、恢复会话、选择模型、发送文件与选区、提示词编辑器，以及可选 tmux 渲染。
- **可选聊天入口**：CodeCompanion 的 Codex ACP、OpenAI HTTP。新聊天时明确选择入口；
  每个标签页显示一个 AI 面板，隐藏会话继续存活。
- **Review rounds**：不可变 Git 快照、CodeDiff 基线比较，以及交回所属会话的反馈草稿。
- **编辑能力**：Oil、Snacks、Treesitter、LSP、补全、格式化、调试和分语言运行器。
- **可选本地灰字**：Minuet 与内置 llama-service。只有附着 UI 且打开合适文件时才启动模型，headless 不加载模型。

当前原生后端只有 Codex。聊天、HTTP 和本地补全与原生终端独立。
Setup 不启动 Agent、聊天、Review 基线或模型。

## 依赖

基础要求为 Neovim **0.12.5+**、Git、ripgrep，以及使用 Nerd Font 的终端。
语言功能依赖各自工具链；Treesitter 构建需要 C 编译器和 tree-sitter-cli **0.26.1+**。

原生终端需要安装并登录 `codex`，`tmux` 用于默认的帧包装。
ACP 聊天额外需要 `codex-acp`；HTTP 聊天读取 `NVIM_OPENAI_API_KEY`，与 CLI 凭证分开。
用 `:checkhealth tillervim` 查看完整依赖报告。

## 安装

先备份已有配置，再把仓库内的 starter 复制到新的配置目录：

```sh
tillervim_source="$(mktemp -d)"
git clone --depth 1 https://github.com/jefyuh/tillervim.git "$tillervim_source"
mkdir -p ~/.config/nvim
cp -R "$tillervim_source/starter/." ~/.config/nvim/
nvim
```

首次启动由 lazy.nvim 安装发行版和依赖。个人配置与 `lazy-lock.json` 提交到你自己的仓库；
通过 `:Lazy` 查看和更新依赖。更新发行版不会改写个人文件。

加载顺序是发行版在前、个人 spec 在后：

```lua
require("lazy").setup({
  spec = {
    { "jefyuh/tillervim", import = "tillervim.plugins" },
    { import = "plugins" },
  },
  defaults = { lazy = true, version = false },
  rocks = { enabled = false },
})
```

完整引导代码见 [starter/](starter/)。Leader 在 `init.lua` 中提前设置，默认是空格；
localleader 默认为逗号。

## 个人配置

```text
~/.config/nvim/
├── init.lua
├── bootstrap.lua      # Early loader/cwd validation
├── lua/config/
│   ├── lazy.lua       # 插件管理和 import
│   ├── options.lua    # 默认编辑器设置之后应用 vim.opt / vim.g
│   ├── keymaps.lua    # 默认映射之后应用 vim.keymap.set/del
│   └── autocmds.lua   # 个人自动命令
├── lua/plugins/       # 原生 lazy.nvim spec：新增与覆盖
└── lazy-lock.json     # 实际使用的发行版及插件版本
```

这些个人文件可选，每个只加载一次。Options 在 editor-core 默认值之后、其余启动插件之前加载；
autocmds 和 keymaps 在 `User LazyDone` 加载。Starter 记录自身源码目录，所以用
`nvim -u /path/init.lua` 启动时，配置文件导航也会指向实际的个人配置。

第三方插件直接使用它的文档接口。例如 `lua/plugins/oil.lua`：

```lua
return {
  "stevearc/oil.nvim",
  opts = { view_options = { show_hidden = false } },
}
```

合并遵循 lazy.nvim 原有规则：`opts` 表合并，复杂列表修改使用函数，插件快捷键使用 `keys`。
改到另一个键时，应在原来的模式禁用旧键；也可以直接修改继承的映射列表。
下面同时修改 Dial 的 Normal 和 Visual 递增键，并保留回调、expr 参数和只读保护：

```lua
-- lua/plugins/dial.lua
return {
  "monaqa/dial.nvim",
  keys = function(_, keys)
    for _, key in ipairs(keys) do
      if key[1] == "<C-a>" then key[1] = "<M-a>" end
    end
    return keys
  end,
}
```

普通全局映射直接使用 Neovim：

```lua
-- lua/config/keymaps.lua
vim.keymap.del("n", "<leader>qq")
vim.keymap.set("n", "<leader>qq", "<cmd>confirm qa<cr>", { desc = "Quit all" })
```

没有按动作名查询键位的注册表，也没有共享键位配置语言。
Oil、Snacks 和 Aerial 使用各自原生的映射选项；which-key 负责展示，`<leader>?` 读取实际安装的映射。

自有功能包提供自己的选项和可调用 API。例如：

```lua
-- lua/plugins/agent.lua
return {
  "agent-workbench.nvim",
  opts = { terminal = { provider = "native" }, panel = { width = 100 } },
}
```

详细接口见 [Agent Workbench](local-plugin/agent-workbench.nvim/README.md)、
[editor-core](local-plugin/editor-core.nvim/README.md)、
[git-review](local-plugin/git-review.nvim/README.md) 和
[llama-service](local-plugin/llama-service.nvim/README.md)。
个人配置不需要修改安装目录中的私有 `tillervim.config.*` 模块。

## 常用按键

| 前缀或按键 | 用途 |
| --- | --- |
| `;` | 找文件、符号或位置 |
| `,` | 当前文件或视图中的操作 |
| `s` | 管理窗口 |
| `<leader>` | AI、Git、调试、UI、会话等全局领域 |
| `<leader>an` / `al` | 新建 / 切换 AI 聊天 |
| `<leader>ac` / `af` | 显示隐藏 / 聚焦 AI 聊天 |
| `<leader>ar` / `aR` / `am` | 恢复 / 继续 / 选择原生模型 |
| `<leader>ab` / `as` / `ai` | 添加文件 / 选区 / 编辑提示词 |
| `<leader>aV` / `av` | 开始 Review round / 查看基线之后的变化 |
| Git 视图中的 `,C` | 编写反馈 |
| `<leader>ax` / `ae` | 选择 HTTP key profile / 行内编辑 |
| `<leader>?` | 查看实时按键指南 |

原生 Codex 默认参数为 `--no-alt-screen --yolo`；通过 `agent-workbench.nvim` 的
`opts.native.codex.args` 修改启动策略。HTTP 读取 `NVIM_*` key 变量，Codex ACP 使用
ChatGPT 登录，不改写计费环境变量。

完整编辑、调试和 Review 工作流见[手册](docs/MANUAL_CN.md)。

## 开发

仓库根 `init.lua` 是源码开发和测试入口；用户从 `starter/init.lua` 开始。
发行版模块位于 `lua/tillervim/`，本地功能包按自身源码位置寻找脚本。

```sh
make verify                 # 空白检查、启动和完整测试
make test S="dial user_config"
make health
```

测试顺序执行，使用离线 Agent 替身，不启动真实 AI turn。
个人配置集成测试会启动独立宿主，验证插件原生覆盖、旧映射移除、加载顺序和 profile 改名。
