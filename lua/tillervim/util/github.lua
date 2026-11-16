-- Git/GitHub dashboard content. Requiring this helper runs no commands;
-- the host calls dashboard_sections only when the dashboard renders its feed.
local M = {}

-- Keep gh failures inside the section, with their original output. The inner
-- process has no terminal input and cannot prompt or probe a noninteractive TTY.
local function dashboard_gh(args)
  return vim.list_extend({
    "sh", "-c", [[
    unset GH_FORCE_TTY
    if output=$(GH_PROMPT_DISABLED=1 GH_PAGER=cat GH_NO_UPDATE_NOTIFIER=1 GH_NO_EXTENSION_UPDATE_NOTIFIER=1 NO_COLOR=1 gh "$@" </dev/null 2>&1); then
      printf '%s\n' "$output"
    else
      printf 'GitHub unavailable\n%s\n' "$output"
    fi
    ]], "dashboard-gh",
  }, args)
end

---Content and actions for the host dashboard; the renderer owns pane geometry.
---@return table[]
function M.dashboard_sections()
  -- Bare-repo controller directories are not worktrees, even when Snacks can
  -- resolve a root for them. GitHub repo feeds also need a GitHub remote.
  local toplevel = vim.fn.system({ "git", "rev-parse", "--is-inside-work-tree" })
  local in_git = vim.v.shell_error == 0 and vim.trim(toplevel) == "true"
  local has_gh = vim.fn.executable("gh") == 1
  local remotes = in_git and vim.fn.system({ "git", "remote", "-v" }) or ""
  local has_gh_remote = in_git and remotes:find("github", 1, true) ~= nil
  return {
    {
      title = "Notifications",
      cmd = dashboard_gh({ "api", "notifications?per_page=5", "--template",
        [[{{range .}}{{tablerow (timeago .updated_at) ]]
        .. [[(.repository.full_name | truncate 18) ]]
        .. [[(.subject.title | truncate 24)}}{{end}}{{tablerender}}]],
      }),
      action = function() vim.ui.open("https://github.com/notifications") end,
      key = "n",
      icon = "󰂚 ",
      height = 5,
      -- Notifications are account-wide, including outside Git repositories.
      enabled = has_gh,
    },
    {
      title = "Open Issues",
      cmd = dashboard_gh({ "issue", "list", "-L", "3" }),
      -- Uppercase opens the picker; lowercase i on the left opens the webpage.
      key = "I",
      action = function() Snacks.picker.gh_issue() end,
      icon = "󰨰 ",
      height = 7,
      enabled = has_gh and has_gh_remote,
    },
    {
      title = "Open PRs",
      cmd = dashboard_gh({ "pr", "list", "-L", "3" }),
      key = "O",
      action = function() Snacks.picker.gh_pr() end,
      icon = "󰜘 ",
      height = 7,
      enabled = has_gh and has_gh_remote,
    },
    {
      title = "Git Status",
      cmd = "git --no-pager diff --stat -B -M -C",
      icon = "󰊢 ",
      height = 10,
      enabled = in_git,
    },
  }
end

return M
