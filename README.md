# My Personal Dotfiles: Kitty & Neovim

This repository houses my personal configuration files (dotfiles) for the Kitty terminal emulator and the Neovim editor.

## 🐱 Kitty

My Kitty setup focuses on a clean look, efficient keybindings, and themes.

*   **Configuration:** Main settings are in `kitty/kitty.conf`.
*   **Keymaps:** Custom keybindings are defined in `kitty/config/keymap.conf`.
*   **Options:** Specific terminal options are set in `kitty/config/options.conf`.
*   **Themes:** Various themes are available under `kitty/theme/`, including Dracula, Tokyo Night, and a custom diff theme.

## ✨ Neovim (LazyVim based)

My Neovim configuration leverages `lazy.vim` for plugin management, featuring a modular structure, LSP integration, and various UI/UX enhancements.

*   **Plugin Management:** Uses `lazy.vim` for declarative and fast plugin loading (`nvim/lazy-lock.json` tracks plugin versions).
*   **Entry Point:** The main configuration starts at `nvim/init.lua`.
*   **Modular Structure:** Configuration is broken down into logical units under `nvim/lua/`:
    *   `nvim/lua/config/`: Core Neovim settings (options, keymaps, autocommands).
    *   `nvim/lua/plugins/`: Plugin specifications managed by `lazy.vim`.
*   **LSP Integration:** Configured for Language Server Protocol support.
*   **File Navigation & Fuzzy Finding:** Likely uses plugins like `neo-tree.nvim` and `fzf-lua.nvim` (configured within `nvim/lua/plugins/`).
*   **Customization:** Includes custom keymaps, UI enhancements (statusline, themes), and potentially AI assistant integration.

<img width="400" alt="start" src="https://github.com/user-attachments/assets/a946ebfe-6152-4e14-8c26-b75768a92b45" />
<br />
<img width="400" alt="auto_cmp" src="https://github.com/user-attachments/assets/4a37b9a9-0427-4188-b56f-a18b6e430c01" />
<br />
<img width="400" alt="trouble" src="https://github.com/user-attachments/assets/c8d88dca-4877-4ff9-a87f-7be0d17c286a" />
<br />
<img width="400" alt="fzf" src="https://github.com/user-attachments/assets/abf2bf22-25b6-4a10-84a2-53cb9fa71a06" />

## 🚀 Installation


### Prerequisites

*   Kitty terminal emulator.
*   Neovim (v0.9.0 or later recommended).
*   Git.
*   A Nerd Font installed and configured in your terminal for icons (required by some Neovim plugins).
*   (Optional but recommended for Neovim) `ripgrep` for fuzzy finding, `fd` for file searching.

### Steps

1.  **Clone the repository:**
    ```bash
    git clone <repository-url> ~/your/local/workspace/dotfiles # Or your preferred location
    ```

2.  **Symlink configurations:**
    ```bash
    # Backup existing configs first!
    # mv ~/.config/kitty ~/.config/kitty.bak
    # mv ~/.config/nvim ~/.config/nvim.bak
    # mv ~/.local/share/nvim ~/.local/share/nvim.bak
    # mv ~/.local/state/nvim ~/.local/state/nvim.bak
    # mv ~/.cache/nvim ~/.cache/nvim.bak

    ln -s ~/your/local/workspace/dotfiles/kitty ~/.config/kitty
    ln -s ~/your/local/workspace/dotfiles/nvim ~/.config/nvim
    ```

3.  **Launch Neovim:**
    ```bash
    nvim
    ```
    `lazy.vim` should automatically bootstrap itself and install all the configured plugins on the first launch.

4.  **Launch Kitty:** Simply start Kitty, and it should pick up the new configuration.

## 📂 Structure Overview

```
.
├── .gitignore
├── README.md
├── kitty/
│   ├── config/
│   │   ├── keymap.conf
│   │   └── options.conf
│   ├── kitty.conf
│   └── theme/
│       ├── diff.conf
│       ├── dracula.conf
│       └── tokyo-night-kitty.conf
└── nvim/
    ├── .editorconfig
    ├── init.lua
    ├── lazy-lock.json
    └── lua/
        ├── config/      # Core Neovim settings
        └── plugins/     # LazyVim plugin specs
```

---

*This configuration is primarily for personal use but feel free to browse and take inspiration.*

