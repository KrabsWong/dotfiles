local function reveal_in_tree(selected)
  if not selected or #selected == 0 then
    return
  end

  local file_path = selected[1]
  local escaped_path = vim.fn.fnameescape(file_path)
  local command_string = "Neotree show reveal=true " .. escaped_path
  local success, err = pcall(vim.cmd, command_string)
end

return {
  "ibhagwan/fzf-lua",
  -- optional for icon support
  dependencies = { "nvim-tree/nvim-web-devicons" },
  -- or if using mini.icons/mini.nvim
  -- dependencies = { "echasnovski/mini.icons" },
  opts = function()
    local actions = require("fzf-lua").actions
    return {
      file_ignore_patterns = { "node_modules", ".git", "vendor" },
      grep = {
        rg_opts = "--hidden --glob=!{node_modules/*,.git/*,vendor/*}",
      },
      files = {
        file_icons = false,
      },
      actions = {
        files = {
          ["enter"] = function(selected, opts)
            actions.file_edit(selected, opts)
            reveal_in_tree(selected)
          end,
          ["ctrl-s"] = actions.file_split,
          ["ctrl-v"] = actions.file_vsplit,
          ["ctrl-t"] = actions.file_tabedit,
          ["alt-q"] = actions.file_sel_to_qf,
          ["alt-Q"] = actions.file_sel_to_ll,
          ["alt-i"] = actions.toggle_ignore,
          ["alt-h"] = actions.toggle_hidden,
          ["alt-f"] = actions.toggle_follow,
        },
        buffers = {
          ["enter"] = function(selected, opts)
            actions.file_edit(selected, opts)
            reveal_in_tree(selected)
          end,
          ["ctrl-s"] = actions.file_split,
          ["ctrl-v"] = actions.file_vsplit,
          ["ctrl-t"] = actions.file_tabedit,
          ["alt-q"] = actions.file_sel_to_qf,
          ["alt-Q"] = actions.file_sel_to_ll,
          ["alt-i"] = actions.toggle_ignore,
          ["alt-h"] = actions.toggle_hidden,
          ["alt-f"] = actions.toggle_follow,
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
  },
}
