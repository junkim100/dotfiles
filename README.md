# Dotfiles

Personal dotfiles and configuration scripts for macOS, Ubuntu, LazyVim, Claude Code, Codex, and Kimi Code.

## Setup

```bash
git clone --recurse-submodules https://github.com/junkim100/dotfiles.git "$HOME/dotfiles"
DOTFILES_DIR="$HOME/dotfiles"
```

Installers derive the repository root from their own location, so the checkout may live anywhere.

The repository is also a Homebrew tap. `Casks/` carries casks that Homebrew itself does not offer, currently the GlobalProtect VPN client, and `macOS/Brewfile` taps the repository by URL so `brew bundle` installs them like any other cask.

All installers in this repository use Bash 3.2 or later and accept `--dry-run` and `--help`. A dry run previews actions, checks tracked symlink sources, and changes nothing, including when invoking another installer. The separate LazyVim installer is only printed during a platform dry run.

Installers show a progress bar for completed stages, the current stage number, and explicit `RUN`, `PLAN`, `SKIP`, and `WARN` messages. Percentages measure stages, not elapsed time. Command output stays visible, and failures stop the installer with the stage and exit status so you can fix the cause and rerun. Terminal output uses color; redirected output and `NO_COLOR=1` stay plain.

Shared installer behavior lives in `scripts/lib/install.sh`, symlink handling in `scripts/link-file`, and installation regression tests in `scripts/tests/installers.sh`. Platform and application installers own the steps specific to them. Downloads use retries, timeouts, and private temporary directories that are removed on exit; downloaded scripts only run after a successful download.

Reruns reuse existing tools and links. Homebrew installs missing Brewfile entries with `--no-upgrade`, apt only runs when packages are missing, and the shared agent installer reuses matching pinned packages and plugins. Updates are separate maintenance actions, such as `brew upgrade` or reviewing new pins in `agents/plugins/catalog.json`. Package managers may still update dependencies required by a missing package.

**macOS:**
```bash
bash "$DOTFILES_DIR/macOS/install.sh"
```

Mac App Store apps are declared in [`macOS/Brewfile`](macOS/Brewfile) using `mas "App Name", id: <App Store ID>`. The Brewfile installs `mas`, the Mac App Store command-line tool, and the macOS installer uses Homebrew Bundle to install missing apps with `--no-upgrade`. On a new Mac, sign into the App Store with the Apple account that owns the apps before running the installer.

Safari is included with macOS. The Brewfile manages its Hush, Noir, and Wipr 2 extensions; enable them in **Safari > Settings > Extensions** after installation. Their individual settings are not stored in dotfiles.

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

**Agents (Codex CLI, Claude Code, Kimi Code, and shared skills):**
```bash
bash "$DOTFILES_DIR/agents/install.sh"
```

The agent installer sets up shared skills and the delegation gate, runs `agents/codex/install.sh`, `agents/claude-code/install.sh`, and `agents/kimi-code/install.sh`, then installs the shared plugin catalog with `agents/plugins/install.sh`. It installs [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) when missing, using OpenAI's native installer non-interactively with `curl` or `wget` on macOS and Linux. The macOS Brewfile leaves Codex installation to this installer. New Codex installations go into `~/.local/bin`; existing installations on `PATH` or at `~/.local/bin/codex`, including Homebrew installations, are reused without upgrading them. The platform shell configurations already add `~/.local/bin` to `PATH`; the installer prints a reminder when needed. Use `--dry-run` to preview installation and skill links without downloading or changing anything.

Custom authored skills live under `agents/skills/`, including `conference-paper-review`, `doubt-driven-development`, `interview`, `paper-study-notes`, `pr-review`, `pr-review-orchestrate`, `quiz`, and `test-audit`. The agent installer links each skill into `~/.agents/skills`, which Codex, [Kimi Code](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/skills.html), [Pi](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/skills.md#locations), and [OpenCode](https://opencode.ai/docs/skills/#place-files) discover directly, leaving room for machine-local skills in the same directory. Pi and OpenCode can discover these skills even when installed later; their applications are installed separately. The Claude Code installer links the same skill directories directly into `~/.claude/skills`.

Third-party plugins are declared once in [`agents/plugins/catalog.json`](agents/plugins/catalog.json). The shared installer verifies pinned upstream archives, stores complete packages under `~/.local/share/agent-plugins`, and configures the same local marketplace for Claude and Codex. Portable skills in both discovery directories point directly to those neutral packages. Run `python3 agents/plugins/manage.py doctor` for a read-only runtime health check. Understand-Anything, frontend-design, Context7, Playwright, and Slack are covered; Pyright's Claude LSP integration is an explicit exception. See the [support matrix and update workflow](agents/plugins/README.md) for per-agent runtime requirements and authentication limits. This shared inventory covers dotfiles-managed capabilities; application-managed connectors and synced caches keep their own lifecycle.

`doubt-driven-development` checks consequential assumptions with focused reproductions, fixtures, or source traces before relying on them. The shared global instructions require automatic use when a wrong assumption could invalidate results, lose data, waste an expensive run, or cause substantial rework. It reuses existing verification and does not initiate reviewer orchestration. The skill is a lightweight adaptation of [Addy Osmani's workflow](https://github.com/addyosmani/agent-skills/blob/main/skills/doubt-driven-development/SKILL.md).

`test-audit` is a portable adaptation of OpenClaw's test-quality skill. It applies lightweight checks when writing, modifying, or reviewing tests, and reserves broader audits for requests that include that scope. Its description supports automatic selection, reinforced by a rule in `agents/AGENTS.md`. Future agents can use the same skill through a supported discovery path; agents with different locations need an installer link, and those with separate global instructions need an equivalent rule for explicit automatic-use guidance.

`agents/AGENTS.md` is the single source of personal instructions for Claude Code, Codex, and Kimi Code, including skill rules, writing preferences, and the delegation gate. The Codex installer links it into `~/.codex/AGENTS.md`, a custom `CODEX_HOME` when set, and Orca's managed Codex home when present. The Claude Code installer links it into `~/.claude/rules/agents.md`, which loads across projects without a `CLAUDE.md`. The Kimi Code installer links it into `~/.kimi-code/AGENTS.md` and a custom `KIMI_CODE_HOME` when set. The repository root `AGENTS.md` separately describes how to maintain dotfiles.

Claude Code 2.1.285 or later is required. Project instructions are configured to include `AGENTS.md` even in repositories that also contain Claude-specific instruction files. The installer reports an older CLI and asks you to run `claude update`; it does not upgrade an existing installation implicitly. No `CLAUDE.md` files or compatibility skill directories are maintained here. The installer removes only the former dotfiles-managed `~/.claude/CLAUDE.md` link after linking the shared rules; it refuses to discard independently authored instructions. See [Claude Code instruction discovery](https://code.claude.com/docs/en/memory#agentsmd) and [global rules](https://code.claude.com/docs/en/memory#user-level-rules).

`agents/jev-delegation/` holds the delegation gate that Orca agents consult before creating or requesting another worker. The installer links the script to `~/.local/bin/jev-delegation` and its protocol and dispatch snippet to `~/.local/share/jev-delegation/`, then creates a virtual environment there from `requirements.txt`. The gate needs a [TypeSafe](https://typesafe.ai) API key in `~/.config/typesafe/api_key` or `TYPESAFE_API_KEY`; the installer warns when neither is present. Without the environment or the key the command still runs and fails closed to `FLAT`, so a broken installation keeps work flat rather than fanning out unchecked. A companion observer, `jev-observe`, is registered as a `PreToolUse` hook in Claude Code's `settings.json` and merged into each Codex `hooks.json`; it records every `worker-start` and whether the gate had been consulted to `~/.local/share/jev-delegation/dispatches.jsonl`. It only observes, never blocks, and always exits zero, because a stalled hook costs a run while a lost audit line costs nothing.

**Kimi Code:**
```bash
bash "$DOTFILES_DIR/agents/kimi-code/install.sh"
```

The standalone installer uses Kimi's official international native installer at `https://code.kimi.ai/kimi-code/install.sh` on macOS and Linux. It downloads and verifies the current native release under `~/.kimi-code/bin/kimi`, then links a managed launcher as `~/.local/bin/kimi` without editing shell files. The launcher defaults `NODE_USE_SYSTEM_CA=1` so OS-trusted certificates work alongside Node's bundled roots; an explicit environment override is preserved. Node.js and Python are not required. Existing commands on `PATH`, at `~/.local/bin/kimi`, or under `~/.kimi-code/bin` are reused; run `kimi upgrade` explicitly when an update is wanted. The installer also links canonical global instructions and shared authored skills, so it works independently of the parent installer. It uses the current Kimi Code CLI, rather than installing the retired Python `kimi-cli` package.

Start `kimi` in your project, enter `/login`, and choose Kimi Code OAuth to use your subscription. Use `/model` to select an available model and `/help` to inspect commands. Credentials, `config.toml`, sessions, and runtime state remain local under `~/.kimi-code` or `KIMI_CODE_HOME`. Existing portable plugin skills in `~/.agents/skills` are discoverable; native MCP servers, hooks, and language-server integrations require Kimi adapters and are not installed by this integration. See the [Kimi Code getting-started guide](https://www.kimi.com/code/docs/en/kimi-code-cli/guides/getting-started).

**Claude Code:**
```bash
bash "$DOTFILES_DIR/agents/claude-code/install.sh"
```

`agents/claude-code/` owns Claude Code settings, the status line, and installation. Its installer links the shared rules and canonical skills, preserving machine-local skills. The standalone Codex installer is `agents/codex/install.sh`; use `agents/install.sh` for the complete shared setup.

```text
agents/
├── AGENTS.md
├── install.sh
├── skills/
├── plugins/
│   ├── catalog.json
│   ├── install.sh
│   ├── manage.py
│   ├── package_store.py
│   └── health.py
├── jev-delegation/
├── claude-code/
│   ├── install.sh
│   ├── settings.json
│   └── statusline-command.sh
├── kimi-code/
│   ├── install.sh
│   └── kimi
└── codex/
    └── install.sh
```

Custom skills imported from claude.ai follow the same ownership rule. The paper skills include their reference files and PDF scanner under `agents/skills/`. Claude Code's `skillOverrides` disables their duplicate `anthropic-skills:<name>` commands, while the local commands use the canonical symlinks. Anthropic's synced skills and cache remain managed by Claude Code. See [synced skill names](https://code.claude.com/docs/en/skills#when-a-synced-skill-name-matches-another-command) and [skill visibility overrides](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings).

## Verification

Run the location-independent repository check before pushing configuration changes:

```bash
"$DOTFILES_DIR/scripts/check"
```

It verifies the shared-configuration symlinks, shell syntax, and tmux settings, and runs every parent-repository installer with `--dry-run` against a temporary home. Because `scripts/link-file` rejects a missing source even in a dry run, this also checks tracked link sources. Isolated command stubs test installation and rerun behavior, failed downloads and package commands, Claude plugin detection, argument handling, temporary-file cleanup, and previews that must not invoke package managers or agent CLIs. These tests do not install real packages or contact the network.

GitHub Actions runs the same check on every push and pull request, defined in `.github/workflows/check.yml`.
