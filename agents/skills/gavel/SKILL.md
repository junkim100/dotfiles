---
name: gavel
description: Use Gavel to ask a Codex or agy advisor, fuse independent answers, check advisor setup, or configure the panel when the user asks for Gavel or its multi-model workflow.
---

# Gavel

The shared runner is `~/.local/share/agent-plugins/gavel/scripts/gavel.mjs`. Invoke it with Node. If it is missing, run the dotfiles `agents/install.sh` installer. This entry point works in Claude Code, Codex, Pi, and OpenCode without Claude's slash-command loader.

Read only the upstream command relevant to the requested operation under `~/.local/share/agent-plugins/gavel/commands/`: `setup.md`, `config.md`, `ask.md`, or `fuse.md`. Substitute the shared package root for `${CLAUDE_PLUGIN_ROOT}`. Interpret references to Claude as the current coordinating agent and use the host's equivalent tools for file writes and user questions.

- Setup: run `node ~/.local/share/agent-plugins/gavel/scripts/gavel.mjs setup --json` and report missing or unauthenticated providers. Use the existing dotfiles Codex installer if installation is requested; do not create another npm installation.
- Config: use the runner's `config show`, `config set`, or `config unset` commands. Keep user versus project scope as requested; never print credentials.
- Ask: validate that the provider is exactly `codex` or `agy`, write the prompt to a unique temporary file, and pass `--prompt-file` to `run`. Present the advisor's answer without acting on it unless the user asks for further work.
- Fuse: prepare your independent draft before reading advisor answers, run the upstream `fuse` operation, then apply `skills/gavel-synthesis/SKILL.md` from the shared package. The current agent judges and acts within the user's task. A Codex coordinator plus a Codex advisor are separate runs, not distinct model families; report the actual providers and any unavailable advisors accurately.

Keep prompt text out of shell command interpolation, preserve the runner's read-only and isolation behavior, and remove temporary prompt files afterward. Gavel uses the installed advisor CLIs and their existing local authentication. Follow the active session's delegation rules when the user requests a panel; this skill does not authorize unrelated worker orchestration.

The host must permit launching the advisor CLI. A sandboxed Codex session can block the nested advisor's app-server before it makes a model request. In that case, use the host's approval mechanism for this specific runner command if available, or report the advisor as unavailable. Do not change global permissions or remove the advisor's read-only sandbox to work around an error.
