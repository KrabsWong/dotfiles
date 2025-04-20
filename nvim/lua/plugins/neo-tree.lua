return {
  "nvim-neo-tree/neo-tree.nvim",
  enabled = true,
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
    "MunifTanjim/nui.nvim",
    -- {"3rd/image.nvim", opts = {}}, -- Optional image support in preview window: See `# Preview Mode` for more information
  },
  lazy = false, -- neo-tree will lazily load itself
  ---@module "neo-tree"
  ---@type neotree.Config?
  cmd = "Neotree",
  keys = {
    {
      "<leader>fe",
      function()
        require("neo-tree.command").execute({ toggle = true, dir = vim.uv.cwd() })
      end,
      desc = "Explorer NeoTree (Root Dir)",
    },
    { "<leader>e", "<leader>fe", desc = "Explorer NeoTree (Root Dir)", remap = true },
  },
  deactivate = function()
    vim.cmd([[Neotree close]])
  end,
  opts = {
    sources = { "filesystem", "buffers", "git_status" },
    source_selector = {
      winbar = true,
    },
    close_if_last_window = true,
    buffers = {
      follow_current_file = {
        enabled = true,
        leave_dirs_open = false,
      },
    },
    filesystem = {
      bind_to_cwd = true,
      follow_current_file = {
        enable = true,
        leave_dirs_open = false,
      },
      use_libuv_file_watcher = true,
      hijack_netrw_behavior = "disabled",
      filtered_items = {
        hide_dotfiles = false,
      },
      remember_last_position = true,
      open_files_do_not_replace_types = { "terminal", "trouble", "qf" },
      window = {
        mappings = {
          ["<tab>"] = "toggle_node",
        },
      },
    },
    event_handlers = {
      {
        event = "neo_tree_buffer_enter",
        handler = function()
          vim.cmd([[highlight! link NeoTreeDirectoryIcon NvimTreeFolderIcon]])
        end,
      },
    },
  },
}

