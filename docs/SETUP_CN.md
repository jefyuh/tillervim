# 初始化与个人配置

将 starter 复制到个人 Neovim 配置目录后，在首次启动编辑器前运行以下命令。命令默认操作脚本所在的 starter，也可以在子命令前加 `--config /path/to/personal`。已有安装先更新 TillerVim 发行版，再从匹配版本的 starter 补入 `bin/tillervim`、`configure.lua` 和 `profile.lua`。使用 `-u` 并存多份配置时，也要合入 [starter 加载器](../starter/lua/config/lazy.lua) 的 runtimepath 处理，确保只读取目标配置的插件覆盖。

```sh
~/.config/nvim/bin/tillervim setup
~/.config/nvim/bin/tillervim sync
~/.config/nvim/bin/tillervim doctor
```

**setup** 展示可选项并将选择保存为个人配置根目录的 `tillervim.json`。回车保留当前值，列表用逗号分隔，输入 `none` 清空。再次执行只更改指定项。下面的配置适合写 Go 和 Python、用树浏览文件、同时使用多种 Agent 的用户。

```sh
~/.config/nvim/bin/tillervim setup --theme tokyonight --explorer tree \
  --languages go,python --completion off \
  --ai codex,antigravity,kimi,opencode,antigravity-acp,kimi-acp,opencode-acp
```

**sync** 通过个人 `init.lua` 使用实际生效的 lazy.nvim 配置，安装缺少的插件和 Mason 包，检查所选解析器能否加载，以及 CodeDiff 原生库是否可用。系统前置或安装目标失败时返回非零，可以修复后重跑。禁用模块会取消其安装请求，已安装的软件留在机器上。插件升级与个人 lockfile 由 lazy.nvim 管理。

**doctor** 在加载插件前检查宿主、所选 SDK、可执行文件及 Codex 登录状态。缺少核心依赖时退出码为非零。可选 CLI 缺失或旧 JDK 会给出状态并继续。进编辑器后用 `:checkhealth tillervim` 查看实际插件、Mason 和各功能的诊断，用 `:AI info` 查看当前会话与入口。

## 选择项目

| 字段 | 可用值和效果 |
| --- | --- |
| `theme` | `solarized-osaka`、`tokyonight`、`catppuccin`、`gruvbox`、`kanagawa`、`rose-pine`、`nightfox`、`everforest`、`onedark`、`nord`、`dracula`、`material`。只引入选中的主题。内置 `default` 无需下载。 |
| `explorer` | `oil` 允许像编辑文本一样批量重命名、移动文件；`tree` 使用 Snacks Explorer 展开目录。两者接管目录参数、`:edit 目录`、dashboard 的 Browse files、`-` 和 `;o`。Oil 的 `;o` 打开浮窗，tree 的 `;o` 打开侧栏。 |
| `languages` | `bash,c,dart,frontend,go,java,json,python,rust,tex,typescript,yaml` 的子集。每个模块一起提供相应的插件、语言服务、格式化、调试和运行器。Lua 属于基础编辑器；临时查看其他文件仍可按需获得语法解析器。 |
| `completion` | `local` 启用可选本地 Minuet 灰字，使用已有的 llama-server 和模型；`off` 跳过 Minuet。普通代码补全独立。 |
| `ai` | 下表的任意组合。空数组关闭预设聊天入口。 |

没有清单的个人配置沿用 Solarized Osaka、Oil、全部语言模块、本地灰字和默认 Codex 终端/ACP 入口。手写 JSON 可以省略使用默认值的字段。用 `setup --defaults` 无交互地接受当前值。普通键位在个人 `lua/config/keymaps.lua` 修改，插件键位、颜色变体和其他插件偏好放进 `lua/plugins/*.lua` 的原生 lazy.nvim spec。修改后重启，新增依赖再运行 sync。示例见 [个人配置](../README_CN.md#个人配置)。

选中 Tokyo Night 后，个人插件 spec 可以返回 `{ { "folke/tokyonight.nvim", opts = { style = "moon" } } }`。Everforest 和 Nord 的上游选项使用 `vim.g`，可在对应 spec 的 `init` 里设置。

例如，个人配置文件可以只声明 Python、文件树和 Kimi 的两个入口。

```json
{
  "theme": "kanagawa",
  "explorer": "tree",
  "languages": ["python"],
  "ai": ["kimi", "kimi-acp"],
  "completion": "off"
}
```

## AI 终端和聊天

| 产品 | 原生 TUI 选项及命令 | CodeCompanion ACP 选项及命令 |
| --- | --- | --- |
| Codex | `codex` → `codex` | `codex-acp` → 独立的 `codex-acp`，ChatGPT 授权 |
| Antigravity | `antigravity` → `agy` | `antigravity-acp` → `agy acp`，需要支持 ACP 的 CLI 版本 |
| Kimi Code | `kimi` → `kimi` | `kimi-acp` → `kimi acp` |
| OpenCode | `opencode` → `opencode` | `opencode-acp` → `opencode acp` |
| [GitHub Copilot CLI](https://docs.github.com/en/copilot/reference/copilot-cli-reference/acp-server) | — | `copilot-acp` → `copilot --acp --stdio` |
| [Mistral Vibe](https://docs.mistral.ai/vibe/code/use-vibe-in-other-ides) | — | `vibe-acp` → `vibe-acp` |

如需独立 HTTP 聊天和 `<Space>ae` 行内编辑，在个人 `lua/plugins/` 的 `agent-workbench.nvim` `opts.providers` 中显式声明 `api` 项（`api_key` 支持 `"$VAR"`、字面量字符串或 `function() -> string|nil`）。

`<Space>an` 新建并选择入口，`<Space>al` 切换，`<Space>ac` 收起或显示。每种 TUI 拥有独立 PTY，收起后进程继续运行。新 TUI 使用上游默认权限和账号，文件或选区作为草稿粘贴；Antigravity 默认通过会话级 `--settings '{"altScreenMode":"always","pickerGrouping":"grouped"}'` 配合独立 `tmux` 帧合成器（`wrap_tmux = true`）实现无撕裂闪烁的全屏渲染、边界滚轮滚动与按工作区分组历史，且 `<Space>ar` 会弹出按当前项目目录隔离的 Antigravity 会话选择器。Kimi 同样支持启动时选会话，三种新增 TUI 均支持继续最近会话。原生 Codex 另有 tmux 渲染、提示词编辑器、逐轮快照和历史读取；其他 Agent 的集成式聊天审阅使用 ACP 入口。协议及启动命令见 [Antigravity](https://antigravity.google/docs/cli/acp)、[Kimi Code](https://moonshotai.github.io/kimi-code/en/reference/kimi-acp.html)、[OpenCode](https://opencode.ai/docs/cli/acp/)。

## 依赖、授权与降级

| 谁负责 | 处理方式 |
| --- | --- |
| 用户准备宿主 | 安装 Neovim ≥ 0.12.5、Git、C 编译器。默认搜索需要 ripgrep，构建解析器需要 tree-sitter CLI ≥ 0.26.1。在 macOS 上，setup 可通过已有 Homebrew 安装缺少的这两个核心工具；无人值守时显式加 `--install-core`。fd、Nerd Font、tmux 属于增强项。 |
| 发行版配齐编辑器依赖 | 先选模块，再由 lazy.nvim、Mason 和 Treesitter 准备插件、编辑器工具与解析器。首次下载需要网络；Mason 失败看 `:MasonLog`。 |
| 用户或项目提供 SDK | 根据项目使用已有的 Node/npm、Python、Go、Rust、Flutter、TeX 或 JDK。Java 项目可继续用 17。当前 jdtls 需要另一个 JDK 25+ 运行，优先检查 JAVA_HOME、SDKMAN 和 PATH。只有 17 时保留编辑与语法高亮，语言服务和 Java 调试等待兼容 JDK；准备好后在已保存的 Java 缓冲区执行 `:edit`。 |
| 用户授权 | Agent CLI 已安装时复用它的账号。启用 Codex 时可用 `setup --login` 调起官方登录。Kimi 可执行 `kimi login`，OpenCode 可执行 `opencode auth login`，Antigravity 在 `agy` 里登录。GitHub 用 `gh auth login`。HTTP key 通过个人配置显式声明（`"$VAR"`、字面量或自定义函数读取凭据管理器）。JSON 和诊断均不输出密钥值。 |

检查终端或 GUI 启动的 Neovim 能读到哪些变量，见[环境变量说明](DIAGNOSTICS.md#environment-variables)。检查模型和工具的实际状态，请在对应的 Neovim 进程中执行 `:checkhealth tillervim`。

## 修改选择与排错

- **保留其他入口。** 指定 `--ai` 或 `--languages` 会替换对应的整个列表。比如从 `kimi` 增加 ACP，请传 `--ai kimi,kimi-acp`。只改主题时只传 `--theme kanagawa`。修改后重启 Neovim，使新的插件清单生效。
- **修复清单。** 遇到 JSON 语法错误、未知名称或重复选项，打开报错路径中的 `tillervim.json` 修正后再运行 setup。提示配置在引导期间被改动时，重跑 setup 会重新读取当前选择。
- **同步中断。** 先运行 doctor 检查核心工具，再重跑 sync。Mason 安装失败看 `:MasonLog`，解析器加载失败按提示执行 `:TSInstall! 解析器名`。若保存选择后取消了 Codex 授权，可单独重跑 `setup --login`。
