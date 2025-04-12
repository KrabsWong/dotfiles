return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  event = "VeryLazy",
  config = function ()
    local configs = require("nvim-treesitter.configs")

    configs.setup({
      ensure_installed = { "lua", "vim", "vimdoc", "javascript", "html", "css", "vue", "typescript" },
      sync_install = false,
      auto_install = true,
      highlight = { enable = true },
      indent = { enable = true },

      -- Incremental selection based on the named nodes from the grammar.
      incremental_selection = {
        enable = true,
        keymaps = {
          init_selection = "<Enter>", -- set to `false` to disable one of the mappings
          node_incremental = "<Enter>",
          scope_incremental = false,
          node_decremental = "<Backspace>",
        },
      },
    })
  end
}
