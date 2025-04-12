return {
  "nvim-neo-tree/neo-tree.nvim",
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
    {
      "<leader>fE",
      function()
        require("neo-tree.command").execute({ toggle = true, dir = vim.uv.cwd() })
      end,
      desc = "Explorer NeoTree (cwd)",
    },
    { "<leader>e", "<leader>fe", desc = "Explorer NeoTree (Root Dir)", remap = true },
    { "<leader>E", "<leader>fE", desc = "Explorer NeoTree (cwd)", remap = true },
  },
  deactivate = function()
    vim.cmd([[Neotree close]])
  end,
  init = function()
    -- FIX: use `autocmd` for lazy-loading neo-tree instead of directly requiring it,
    -- because `cwd` is not set up properly.
    vim.api.nvim_create_autocmd("BufEnter", {
      group = vim.api.nvim_create_augroup("Neotree_start_directory", { clear = true }),
      desc = "Start Neo-tree with directory",
      once = true,
      callback = function()
        if package.loaded["neo-tree"] then
          return
        else
          local stats = vim.uv.fs_stat(vim.fn.argv(0))
          if stats and stats.type == "directory" then
            require("neo-tree")
          end
        end
      end,
    })
  end,
  opts = {
    sources = { "filesystem", "buffers", "git_status" },
    close_if_last_window = false,
    buffers = {
      follow_current_file = {
        enabled = true,
        leave_dirs_open = false,
      },
    },
    filesystem = {
      bind_to_cwd = true,
      follow_current_file = { enable = true },
      use_libuv_file_watcher = true,
      hijack_netrw_behavior = "open_current",
      filtered_items = {
        hide_dotfiles = false,
      },
      remember_last_position = true,
      open_files_do_not_replace_types = { "terminal", "trouble", "qf" },
      window = {
        mappings = {
          ["<tab>"] = "toggle_node"
        }
      }
    },
    event_handlers = {
      {
        event = "neo_tree_buffer_enter",
        handler = function()
          vim.cmd([[highlight! link NeoTreeDirectoryIcon NvimTreeFolderIcon]])
        end,
      }
    }
  },
}
