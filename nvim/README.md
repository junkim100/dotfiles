# nvim

LazyVim, set up as a code reader rather than an IDE: Claude Code does the editing, this navigates and reviews.

Symlinked to `~/.config/nvim` by both `macOS/install.sh` and `ubuntu/install.sh`.

## Reproducibility

Three files pin the setup, so a fresh machine gets the same editor rather than the same starting point:

- `lazy-lock.json` pins all 42 plugins to exact commits. `Lazy! restore` installs those commits; `Lazy! sync` would take latest instead, so the install scripts use `restore`.
- `lazyvim.json` pins which LazyVim extras are enabled.
- `ubuntu/setup_nvim.sh` pins the neovim version itself. apt is not used: Ubuntu ships 0.6 on 22.04 and 0.9.5 on 24.04, and this config needs 0.10+.

Plugin versions only change when you run `:Lazy update` and commit the new lockfile.

## Modifications to stock LazyVim

| | what | why |
|---|---|---|
| 1 | Providers off | Opening a `.py` file made neovim shell out probing for a python3 provider. Measured 104ms startup with them on, 42ms with them off. |
| 2 | Auto-reload on `CursorHold` | LazyVim covers `FocusGained` and `autoread` covers buffer switches, but neither catches a file rewritten while you sit still on it. `swapfile` is off for the same reason. |
| 3 | mason `ensure_installed` filter | Drops `stylua` and `shfmt`, keeps everything else. See the warning below. |
| 4 | nord, transparent | Matches ghostty and tmux. `transparent = true` so ghostty's `background-opacity 0.7` shows through. |
| 5 | treesitter `ensure_installed` filter | Drops the web stack, which appears nowhere in solar-system and costs compile time on every new machine. |
| 6 | Dotfiles visible in pickers | snacks hides them by default, which makes the explorer useless in a dotfiles repo. `ignored` stays false so `.venv` and `__pycache__` do not flood results. |
| 7 | basedpyright, not pyright | Matches the Zed setup this replaced. |
| 8 | Transparent floats | nord's `transparent` only clears `Normal`. Pickers and hover windows draw through `SnacksNormal`/`SnacksPicker*`, which snacks leaves for the colorscheme and nord does not define. |
| 9 | neominimap | Replaces Zed's `"minimap": { "show": "always" }`. `<leader>mm` toggles. |
| 10 | Mouse | `mousescroll=ver:2,hor:4`, and `mousemoveevent` on locally but off over SSH where per-movement events read as lag. |
| 11 | BUILD and Jinja filetypes | 240 pants BUILD files in wbl-eval are Python but carry no extension, so they rendered as plain text. |
| 12 | diffview | Side-by-side changeset review, which lazygit does not do. `<leader>gr` resolves the repo's actual default branch rather than assuming `main`. |

## Warning: filter, do not replace

Both mason and treesitter mark `ensure_installed` as `opts_extend`. Setting it to a fixed list in an override silently discards everything the `lang.*` extras contribute, so enabling `lang.yaml` and friends installs nothing at all. Both overrides in `lua/plugins/overrides.lua` remove only unwanted entries and pass the rest through. Keep them that way.

## Dependencies

Required: `git`, a C compiler (treesitter parsers build from source).

Optional but assumed: `lazygit` for `<leader>gg`, `fd` for fast file finding (snacks falls back to `ripgrep`), `node` for the npm-based language servers — basedpyright, yaml-language-server, json-lsp, bash-language-server, dockerfile-language-server.

Without node, treesitter highlighting still works and go-to-definition does not. `ubuntu/setup_nvim.sh` checks for all of these and reports what is missing rather than failing partway through.
