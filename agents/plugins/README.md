# Shared plugins

`catalog.json` is the source of truth for dotfiles-managed third-party packages, their full upstream commit IDs and archive checksums, and supported clients. Custom authored skills and adapters stay in `agents/skills/`. Source packages, build output, credentials, and native caches stay outside Git.

Run `bash agents/install.sh` for the complete setup. After that, `bash agents/plugins/install.sh` reconciles packages and client integrations independently. Both support `--dry-run`. Python 3, Node, and npm are required for plugins; the installer provisions missing pnpm and Pyright commands under `~/.local/share/agent-plugins/tools` and links them into `~/.local/bin`, reusing existing commands. Native Claude and Codex CLI installations are handled by the parent agent installer.

## Ownership and installation

Verified archives are unpacked into `~/.local/share/agent-plugins/releases/<catalog-digest>/plugins/<name>`. A release contains complete upstream packages, including references, scripts, and assets. The installer checks archive SHA-256 values before extraction, rejects unsafe archive entries, and publishes a release only after validation succeeds. A receipt records hashes of authored files; generated build output may be added without changing those files.

`~/.local/share/agent-plugins/marketplace` points to the selected release. Both clients register this local marketplace as `dotfiles`. Their native caches are installation outputs; shared skills never point into them. Both `~/.agents/skills` and `~/.claude/skills` link directly to the same neutral package files. Deleting either client's cache therefore leaves portable skills intact. Native plugins may also expose namespaced commands such as `understand-anything:understand`.

Native manifest versions include the catalog digest. This keeps package selection consistent across Claude Code, the normal Codex home, a custom `CODEX_HOME`, and Orca's managed Codex home. Installation reuses the selected release and matching native plugins. Changing reviewed pins in the catalog selects a new release; an ordinary rerun does not upgrade upstream versions.

Packaging normalizes native manifest versions and the catalog's declared empty pnpm workspace importers before recording file hashes. Understand-Anything's bundled viewer needs an empty lockfile entry; otherwise pnpm rewrites its lockfile even during a frozen install. These adjustments are explicit and covered by verification.

The migration accepts the previous dotfiles-managed links into Codex's cache and replaces them with neutral links. After each client's replacements are installed and enabled, the installer disables only the old plugin IDs declared in `legacy_id`. Other marketplaces, plugins, real skill directories, and unrelated symlinks remain untouched. Native CLIs may write local marketplace registration into user settings; machine-specific paths must not be committed.

## Support

| Capability | Claude Code | Codex | Muse Code, Pi, OpenCode, and other skill readers |
| --- | --- | --- | --- |
| Custom dotfiles skills | Shared source symlinks | Shared source symlinks | Shared source symlinks |
| Understand-Anything | Native plugin and portable skills | Native plugin and portable skills | Nine portable skills and complete package |
| Gavel | Native commands and shared `gavel` skill | Shared `gavel` entry point and native synthesis skill | Shared `gavel` entry point |
| frontend-design | Native plugin and portable skill | Native plugin and portable skill | Portable skill |
| Context7 | Native MCP plugin | Native MCP plugin | Requires an MCP adapter |
| Playwright | Native MCP plugin | Native MCP plugin | Requires an MCP adapter and browser dependencies |
| Slack | Native plugin and portable skills | Native plugin and portable skills | Eight portable skills; tools require a connection |
| Pyright LSP | Native LSP plugin | Pyright CLI | Use the client's language support or Pyright CLI |

Understand-Anything also has its upstream-supported `~/.understand-anything-plugin` link. Gavel uses `~/.local/share/agent-plugins/gavel`; the custom `gavel` skill reads its upstream command instructions and uses the same Node runner in every agent. Model requests, graph generation, and browser tasks never run during installation. Understand-Anything builds its core on first use.

Understand-Anything's automatic graph-update hooks use Claude events; other agents should request updates explicitly. MCP servers, tool names, language servers, and OAuth connections need client support. Muse Code discovers the portable skills through `~/.agents/skills`, and its application is installed by `agents/muse-code/install.sh`; native Muse plugins, MCP servers, and hooks are not reconciled here. Pi and OpenCode discover the portable skills, but their applications and MCP adapters are not installed here. Application-managed connectors, synced skills, and credentials retain their own lifecycle.

Gavel also needs the host to permit launching its advisor CLI. A sandboxed Codex session may block the nested app-server before a model request. Use an approved runner command when the host supports it; sharing the skill does not override execution permissions. The advisor's read-only sandbox remains enabled.

## Verification and updates

Run `python3 agents/plugins/manage.py doctor`, or add `--json` for structured output. This check reads files only: it does not launch agent CLIs, access credentials, make network requests, repair links, or change configuration. It checks release integrity, shared links, expected native versions and enablement, MCP definitions, and available runtime commands. Failures return nonzero; optional dependency warnings are reported separately. It does not establish OAuth authorization, browser availability, or model execution; test those through the active client when needed.

`python3 agents/plugins/manage.py check` validates the catalog and Claude's tracked enabled-plugin settings. `scripts/check` also runs isolated tests for archive integrity, native installation and reruns, cache independence, failure propagation, local-content protection, and the health check's read-only behavior.

To update a package, review its upstream change, update its full commit and archive checksum in the catalog, run the tests, and rerun `agents/install.sh`. The new catalog digest changes all native package versions, making the selected release explicit. Keep the previous release until the new one is verified. Never copy OAuth grants between agents. Start new sessions after installation so discovery reflects the current packages.

Upstream references: [Understand-Anything](https://github.com/Egonex-AI/Understand-Anything), [Gavel](https://github.com/junkim100/gavel), and [Codex plugin packaging](https://developers.openai.com/plugins/build/plugins).
