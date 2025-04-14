return {
  "ibhagwan/fzf-lua",
  -- optional for icon support
  dependencies = { "nvim-tree/nvim-web-devicons" },
  -- or if using mini.icons/mini.nvim
  -- dependencies = { "echasnovski/mini.icons" },
  opts = {
    file_ignore_patterns = { "node_modules", ".git", "vendor" },
    grep = {
      rg_opts = "--hidden --glob=!{node_modules/*,.git/*,vendor/*}"
    },
  },
  keys = {
    {
      "<leader>ff",
      function() require("fzf-lua").files() end,
      desc = "Find Files in project directory"
    },
    {
      "<leader>fg",
      function() require("fzf-lua").live_grep() end,
      desc = "Find by grepping in project directory"
    },
    {
      "<leader>fc",
      function() require("fzf-lua").files({ cwd = vim.fn.stdpath("config") }) end,
      desc = "Find in neovim configuration"
    }
  }
}
