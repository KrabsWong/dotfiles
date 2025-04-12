return {
  "catppuccin/nvim",
  config = function()
    require("catppuccin").setup({
      compile=true
    })
    vim.cmd("colorscheme catppuccin-macchiato")
  end
}
