# Dotfiles

Personal dotfiles and configuration scripts for macOS, Ubuntu, LazyVim, Claude Code, and Codex.

## Setup

```bash
git clone --recurse-submodules https://github.com/junkim100/dotfiles.git "$HOME/dotfiles"
DOTFILES_DIR="$HOME/dotfiles"
```

Installers derive the repository root from their own location, so the checkout may live anywhere.

The repository is also a Homebrew tap. `Casks/` carries casks that Homebrew itself does not offer, currently the GlobalProtect VPN client, and `macOS/Brewfile` taps the repository by URL so `brew bundle` installs them like any other cask.

All installers in this repository use Bash 3.2 or later and accept `--dry-run` and `--help`. A dry run previews actions, checks tracked symlink sources, and changes nothing, including when invoking another installer. The separate LazyVim installer is only printed during a platform dry run.

Installers show a progress bar for completed stages, the current stage number, and explicit `RUN`, `PLAN`, `SKIP`, and `WARN` messages. Percentages measure stages, not elapsed time. Command output stays visible, and failures stop the installer with the stage and exit status so you can fix the cause and rerun. Terminal output uses color; redirected output and `NO_COLOR=1` stay plain.

Shared installer behavior lives in `scripts/lib/install.sh`, symlink handling in `scripts/link-file`, and installation regression tests in `scripts/tests/installers.sh`. Platform and application installers keep their existing entry points and own the steps specific to them. Downloads use retries, timeouts, and private temporary directories that are removed on exit; downloaded scripts only run after a successful download.

Reruns reuse existing tools and links. Homebrew installs missing Brewfile entries with `--no-upgrade`, apt only runs when packages are missing, and Claude Code skips existing marketplaces and user plugins. Updates are separate maintenance actions, such as `brew upgrade` or `claude plugin update <plugin>@<marketplace>`. Package managers may still update dependencies required by a missing package.

**macOS:**
```bash
bash "$DOTFILES_DIR/macOS/install.sh"
```

**Ubuntu:**
```bash
bash "$DOTFILES_DIR/ubuntu/install.sh"
```

**Backend.AI profile on Ubuntu:**
```bash
bash "$DOTFILES_DIR/profiles/backend-ai/install.sh"
```

The Backend.AI profile reuses the Ubuntu Conda installer and shared tmux installer. It refuses to replace a real `~/.cache` directory; relocate its contents to the profile's cache destination before using the profile. Existing system tmux installations are reused without requiring a Conda copy.

Ubuntu reports missing apt packages when passwordless sudo is unavailable. It exposes Ubuntu's `batcat` as `~/.local/bin/bat` without renaming the package-owned binary. `nvitop` uses uv, pipx, or a dedicated virtual environment under `~/.local/share/dotfiles/nvitop`, never apt or the system Python environment. The Conda installer supports Linux x86_64 and ARM64 and refuses to overwrite an incomplete installation.

Configuration shared by two or more platforms lives under `common/`. This currently includes tmux, Bat, Ranger, Git defaults, and the Everforest Ghostty theme. Platform Git files include the shared defaults and remain available for platform-specific overrides. Compatibility symlinks at old paths keep existing installations working.

The shared tmux installer links the canonical configuration and installs TPM, tmux-resurrect, and tmux-continuum. Sessions save every 15 minutes, restore when tmux starts, and start automatically after login on supported macOS and Linux systems.

**LazyVim:**
```bash
git -C "$DOTFILES_DIR" submodule update --init --recursive lazyvim
bash "$DOTFILES_DIR/lazyvim/install.sh"
```

The configuration lives in [`junkim100/lazyvim`](https://github.com/junkim100/lazyvim) and is pinned here as a Git submodule. Its installer links the checkout to `~/.config/nvim`, installs the pinned Neovim release, and restores exact plugin commits from `lazy-lock.json`.

**Codex CLI and shared agent skills (Codex, Pi, OpenCode, and Claude Code):**
```bash
bash "$DOTFILES_DIR/agents/install.sh"
```

The agent installer installs [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) when missing, using OpenAI's native installer non-interactively with `curl` or `wget` on macOS and Linux. New installations go into `~/.local/bin`; existing installations on `PATH` or at `~/.local/bin/codex`, including Homebrew installations, are reused without upgrading them. The platform shell configurations already add `~/.local/bin` to `PATH`; the installer prints a reminder when needed and does not edit shell configuration. Use `--dry-run` to preview installation and skill links without downloading or changing anything.

All repository-managed skills live under `agents/skills/`, including `conference-paper-review`, `interview`, `paper-study-notes`, `pr-review`, and `quiz`. The agent installer links each skill into `~/.agents/skills`, which Codex, [Pi](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/skills.md#locations), and [OpenCode](https://opencode.ai/docs/skills/#place-files) discover directly, leaving room for machine-local skills in the same directory. Pi and OpenCode can discover these skills even when installed later; their applications are installed separately. Claude Code receives its links through the installer below.

`agents/AGENTS.md` holds the global instructions for agents that read `AGENTS.md`. The installer links it to `$CODEX_HOME/AGENTS.md`, which is `~/.codex/AGENTS.md` for a plain terminal. Orca points `CODEX_HOME` at its own managed home, so its Codex workers read a different global file; the installer links that copy too when Orca is present, and skips it otherwise. The Claude Code equivalent is `claude-code/CLAUDE.md`, and the delegation gate section is duplicated in both because no instruction file is shared across agents.

`agents/jev-delegation/` holds the delegation gate that Orca agents consult before creating or requesting another worker. The installer links the script to `~/.local/bin/jev-delegation` and its protocol and dispatch snippet to `~/.local/share/jev-delegation/`, then creates a virtual environment there from `requirements.txt`. The gate needs a [TypeSafe](https://typesafe.ai) API key in `~/.config/typesafe/api_key` or `TYPESAFE_API_KEY`; the installer warns when neither is present. Without the environment or the key the command still runs and fails closed to `FLAT`, so a broken installation keeps work flat rather than fanning out unchecked.

**Claude Code:**
```bash
bash "$DOTFILES_DIR/claude-code/install.sh"
```

`claude-code/` owns Claude Code settings, instructions, the status line, and installation. Its installer links the same canonical skills from `agents/skills/` into `~/.claude/skills`, preserving machine-local skills. `claude-code/skills/` contains only compatibility symlinks, including the `pr` alias for `pr-review`; existing home-directory links through those paths keep working.

Custom skills imported from claude.ai follow the same ownership rule. The paper skills include their reference files and PDF scanner under `agents/skills/`. Claude Code's `skillOverrides` disables their duplicate `anthropic-skills:<name>` commands, while the local commands use the canonical symlinks. Anthropic's synced skills and cache remain managed by Claude Code. See [synced skill names](https://code.claude.com/docs/en/skills#when-a-synced-skill-name-matches-another-command) and [skill visibility overrides](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings).

## Verification

Run the location-independent repository check before pushing configuration changes:

```bash
"$DOTFILES_DIR/scripts/check"
```

It verifies the shared-configuration symlinks, shell syntax, and tmux settings, and runs every parent-repository installer with `--dry-run` against a temporary home. Because `scripts/link-file` rejects a missing source even in a dry run, this also checks tracked link sources. Isolated command stubs test installation and rerun behavior, failed downloads and package commands, Claude plugin detection, argument handling, temporary-file cleanup, and previews that must not invoke package managers or agent CLIs. These tests do not install real packages or contact the network.

GitHub Actions runs the same check on every push and pull request, defined in `.github/workflows/check.yml`.
