local function reveal_in_tree(selected)
  if not selected or #selected == 0 then
    return
  end

  local file_path = selected[1]
  local escaped_path = vim.fn.fnameescape(file_path)
  local command_string = "Neotree show reveal=true " .. escaped_path
  local success, err = pcall(vim.cmd, command_string)
end

local function grep_reveal_in_tree(grep_selected)
  if #grep_selected > 0 and type(grep_selected[1] == "table" and #grep_selected[1] > 0) then
    local grep_string = grep_selected[1]

    local file_path_pos = string.find(grep_string, ":", 1, true)
    local file_path

    if file_path_pos then
      file_path = string.sub(grep_string, 1, file_path_pos - 1)
      print(vim.inspect(file_path))
      if file_path and type(file_path) == "string" then
        reveal_in_tree({ file_path })
      end
    end
  end
end

return {
  "ibhagwan/fzf-lua",
  -- optional for icon support
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = { "VeryLazy", "CmdlineEnter" },
  -- or if using mini.icons/mini.nvim
  -- dependencies = { "echasnovski/mini.icons" },
  opts = function()
    local actions = require("fzf-lua").actions
    return {
      file_ignore_patterns = { "node_modules", ".git", "vendor", "dist", "*.lock", "*-lock.json", "build", "bin" },
      files = {
        file_icons = false,
        actions = {
          ["enter"] = function(selected, opts)
            actions.file_edit(selected, opts)
            reveal_in_tree(selected)
          end,
        },
      },
      grep = {
        file_icons = false,
        rg_opts = "--hidden --glob=!{node_modules/*,.git/*,vendor/*}",
        actions = {
          ["enter"] = function(selected, opts)
            actions.file_edit(selected, opts)
            grep_reveal_in_tree(selected)
          end,
        },
      },
    }
  end,
  keys = {
    {
      "<leader>ff",
      function()
        require("fzf-lua").files()
      end,
      desc = "Find Files in project directory",
    },
    {
      "<leader>fg",
      function()
        require("fzf-lua").live_grep()
      end,
      desc = "Find by grepping in project directory",
    },
    {
      "<leader>fc",
      function()
        require("fzf-lua").files({ cwd = vim.fn.stdpath("config") })
      end,
      desc = "Find in neovim configuration",
    },
    {
      "<leader>gf",
      function()
        require("fzf-lua").git_bcommits()
      end,
      desc = "Get git commit history",
    },
  },
}
