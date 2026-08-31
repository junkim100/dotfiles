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
| 1 | Providers off | Opening a `.py` file made neovim shell out probing for a python3 provider. Measured 104ms startup with them on, 46ms with them off. |
| 2 | Auto-reload on `CursorHold` | LazyVim covers `FocusGained` and `autoread` covers buffer switches, but neither catches a file rewritten while you sit still on it. `swapfile` stays at its default (on): swap conflicts come from a crashed session or two nvim instances on one file, not from a file changing on disk. |
| 3 | *(removed)* | Formerly filtered `stylua`/`shfmt` out of mason. The reasoning went stale once the config moved into dotfiles: stylua formats this config and shfmt formats the install scripts, both hand-edited. |
| 4 | everforest, transparent | Matches Ghostty and OMP. Dark Medium keeps the shared palette, and transparency level 2 lets Ghostty's background opacity show through. |
| 5 | *(removed)* | Formerly trimmed the web stack out of treesitter's `ensure_installed`, on the claim that it appears nowhere in solar-system. It does: 23 html, 29 js, 28 css, 2 ts, and 3 tsx files, several inside the vendored trees `/pr` exists to review. Removed in ff87844; those files highlight again. |
| 6 | Dotfiles visible in pickers | snacks hides them by default, which makes the explorer useless in a dotfiles repo. `ignored` stays false so `.venv` and `__pycache__` do not flood results. |
| 7 | basedpyright, not pyright | Matches the Zed setup this replaced. |
| 8 | Transparent floats | Everforest clears its core highlights, but pickers and hover windows draw through plugin-specific groups. Those backgrounds are cleared while preserving their existing foreground and style attributes. |
| 9 | neominimap | Replaces Zed's `"minimap": { "show": "always" }`. `<leader>mm` toggles. `diagnostic.severity` is filtered to errors: the default annotation mode paints the whole minimap row in the diagnostic's colour, so warnings turned the map into a yellow bar. |
| 10 | Mouse | `mousescroll=ver:2,hor:4`, and `mousemoveevent` on locally but off over SSH where per-movement events read as lag. |
| 11 | BUILD and Jinja filetypes | 240 pants BUILD files in wbl-eval are Python but carry no extension, so they rendered as plain text. |
| 12 | diffview | Side-by-side changeset review, which lazygit does not do. `<leader>gr` resolves the repo's actual default branch rather than assuming `main`. |
| 13 | Formatters for json, toml, yaml | Stock LazyVim wires conform for lua, sh, markdown, and fish only, leaving the rest to conform's LSP fallback. That fallback is not dependable: taplo attaches to a `.toml` buffer advertising `textDocument/formatting` and the fallback still does nothing. Naming the formatter per filetype makes it deterministic. |
| 14 | `root_spec = { "cwd" }` | LazyVim's default walks up to `.git`, which in a monorepo means launching nvim from `eval/wbl-eval` roots the explorer at `solar-system` and greps the whole repo. Leaving `lsp` in the chain fixes the common case but narrows without warning inside vendored trees. |
| 15 | Quiet diagnostics in markdown, yaml, and BUILD | markdownlint fires MD013 on nearly every paragraph, because prose here is one logical line per paragraph rather than wrapped at a column. yamlls validates against the whole SchemaStore catalogue and flags correct-but-unrecognised keys. BUILD files are filetype python, so basedpyright reports `python_sources()` as an undefined name on every one of them. Virtual text, underline, and signs go off together in those buffers: suppressing only the inline text still left an undercurl on most lines. The diagnostics themselves survive for `<leader>xx` and `<leader>cd`. json is deliberately not in the list, since a diagnostic there is usually a real missing comma. |
| 16 | No spell checking | LazyVim turns `spell` on for text, plaintex, typst, gitcommit, and markdown, and nothing in the neovim runtime does, so that one autocmd is the whole story. Its `lazyvim_wrap_spell` group is re-created here with the `wrap` half kept, since prose is one line per paragraph and needs soft wrap to be readable. |
| 17 | Absolute line numbers | LazyVim sets both `number` and `relativenumber`, so the whole gutter renumbers on every cursor move. `<leader>uL` toggles relative back for a session. |
| 18 | basedpyright at `standard` | basedpyright defaults to `recommended`, much stricter than the pyright default LazyVim was written against: `reportAny` and `reportUnknown*` fire on every value coming from an untyped library. Six lines of ordinary python produced eight diagnostics; `standard` takes the same file to one and still catches a real `x: int = "not an int"`. The two import rules are off because pants runs with `enable_resolves = false` and resolves each target into its own sandbox, so no interpreter exists that could resolve a third-party import in solar-system. |
| 19 | OSC 52 clipboard over SSH | LazyVim leaves `clipboard` empty when `SSH_CONNECTION` is set, and neovim's provider search then picks pbcopy, which fills the clipboard of the host nvim runs on rather than the machine in front of you. Paste stays on the last yank rather than reading the clipboard: tmux does not pass the terminal's response to an OSC 52 read back. Requires `set-clipboard on` in tmux, which the default of `external` is not; both tmux configs in this repo set it. |
| 20 | `<leader>qx` deletes a session | persistence.nvim can list, load, and pick sessions but has no way to remove one, so clearing out a directory you have since renamed meant deleting the file by hand. Dedupes by file rather than by directory, unlike its own `select()`, so per-branch sessions are visible. |
| 21 | render-markdown's headings and checkboxes | The markdown extra already renders bullets, tables, code blocks, blockquotes, and concealed emphasis, but LazyVim sets `heading.icons = {}` and `checkbox.enabled = false`, which are the two most visible parts. With them off a `.md` buffer reads as though nothing is rendering when nearly all of it is. The line under the cursor still shows raw source, which is render-markdown working as intended, not a gap. |

## Warning: filter, do not replace

There is no `ensure_installed` override in this config any more, and if you add one, filter rather than replace.

Both mason and treesitter mark `ensure_installed` as `opts_extend`. Setting it to a fixed list silently discards everything the `lang.*` extras contribute, so enabling `lang.docker` and then pinning the list installs no Dockerfile parser at all. Take `opts` in its function form, drop the entries you do not want, and pass the rest through.

The same applies to `formatters_by_ft` in `lua/plugins/format.lua`: LazyVim has already populated that table, so assigning a fresh one drops lua and sh.

## Formatting

`<leader>cf` formats. Verified working on all seven types this repo uses:

| filetype | formatter |
|---|---|
| lua | stylua |
| sh | shfmt |
| json, jsonc | prettier |
| yaml | prettier |
| toml | taplo |
| markdown | prettier, markdownlint-cli2, markdown-toc |
| python | ruff |

## Dependencies

Required: `git`, a C compiler (treesitter parsers build from source).

`ripgrep` is also required, not optional: snacks hardcodes `rg` for its grep source with no fallback, so `<leader>/` does nothing without it. On Ubuntu, `setup_nvim.sh` installs neovim, lazygit, ripgrep, and fd as static binaries into `~/.local`, so none of them need root or apt.

Optional: `fd` for faster file finding (it degrades to `ripgrep`, then `find`).

Language servers come from three ecosystems, and `bootstrap-mason.lua` reads which from each package's registry entry rather than assuming, so it installs whatever the machine can actually build:

| source | needs | packages |
|---|---|---|
| github | nothing | ruff, marksman, taplo, lua-language-server, shellcheck, hadolint |
| pypi | `python3` | basedpyright |
| npm | `node` | yaml-language-server, json-lsp, dockerfile-language-server, docker-compose-language-service, bash-language-server, markdownlint-cli2, markdown-toc |

The split matters on the GPU boxes. `python3` is a safe bet there and `node` is not, and basedpyright is a pypi package, so **Python keeps full go-to-definition on a machine with no node at all** — seven of the fourteen install. An earlier version gated the whole run on `node` and got zero.

`ubuntu/setup_nvim.sh` reports what is missing rather than failing partway through.
