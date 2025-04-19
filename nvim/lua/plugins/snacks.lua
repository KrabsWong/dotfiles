---@module 'snacks'

---
return {
  "folke/snacks.nvim",
  enabled = false,
  ---@type snacks.Config
  opts = {
    indent = {},
    explorer = {
      enabled = true,
      auto_close = false,
      replace_netrw = true,
      hidden = true,
      follow_file = true,
    },
    buffers = {
      hidden = false,
   }
  },
  keys = {
    {
      "<leader>fe",
      function()
        Snacks.explorer()
      end,
      desc = "Explorer Snacks (root dir)",
    },
    { "<leader>e", "<leader>fe", desc = "Explorer Snacks (root dir)", remap = true },
  },
}
