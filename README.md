# My Personal Neovim Configuration

This repository stores my personal Neovim configuration files. It's built upon the modern [`lazy.vim`](https://github.com/folke/lazy.nvim) plugin manager, aiming for a fast, modular, and efficient development environment tailored to my workflow.

## ✨ Features

*   **Plugin Management:** Uses `lazy.vim` for declarative and fast plugin loading.
*   **Modular Structure:** Configuration is broken down into logical units under the `lua/` directory (e.g., `config/` for core settings, `plugins/` for plugin specifications).
*   **LSP Integration:** Configured for Language Server Protocol support, enabling features like autocompletion, diagnostics, code actions, etc. (Specific LSP servers might need separate installation).
*   **File Navigation:** Includes file tree explorers like `neo-tree.nvim`.
*   **Fuzzy Finding:** Leverages tools like `telescope.nvim` or `fzf-lua` for quick searching across files, buffers, commands, etc.
*   **Terminal Integration:** Seamless terminal access within Neovim using `toggleterm.nvim`.
*   **Custom Keymaps:** Sensible and ergonomic keybindings defined in `lua/config/keymaps.lua`.
*   **UI Enhancements:** Customized statusline, potentially themes, and other visual improvements.
*   **AI Assistant:** Integration with AI coding tools via `avante.nvim`.
*   *(Add any other specific features or plugins you rely on heavily)*

## 🚀 Installation

1.  **Prerequisites:**
    *   Neovim (v0.9.0 or later recommended).
    *   Git.
    *   A Nerd Font installed and configured in your terminal for icons.
    *   (Optional but recommended) `ripgrep` for fuzzy finding, `fd` for file searching.

2.  **Clone the repository:**
    ```bash
    # Backup your existing nvim config first if you have one
    # mv ~/.config/nvim ~/.config/nvim.bak
    # mv ~/.local/share/nvim ~/.local/share/nvim.bak
    # mv ~/.local/state/nvim ~/.local/state/nvim.bak
    # mv ~/.cache/nvim ~/.cache/nvim.bak

    ```

3.  **Launch Neovim:**
    ```bash
    nvim
    ```
    `lazy.vim` should automatically bootstrap itself and install all the configured plugins on the first launch.

## 📂 Structure

*   `init.lua`: The main entry point for the configuration.
*   `lua/config/`: Core Neovim settings (options, keymaps, autocommands).
*   `lua/plugins/`: Plugin specifications managed by `lazy.vim`. Each file typically configures one or more related plugins.

---

*This configuration is primarily for personal use but feel free to browse and take inspiration.*
```

