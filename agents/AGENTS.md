# AGENTS.md

Global instructions for Codex and other agents that read `AGENTS.md`. Installed by `agents/install.sh` to `$CODEX_HOME/AGENTS.md`, and to Orca's managed Codex home when Orca is present.

The Claude Code equivalent lives in `claude-code/CLAUDE.md`. Keep the delegation gate below in sync with the copy there.

# Orca Delegation Gate

**Inside an Orca Run, run `jev-delegation` before creating or requesting any additional worker.**

- Applies in two roles only. You are a dispatched worker if your preamble names a coordinator terminal handle and a dispatch capability. You are the root coordinator if you drive an Orca Run and were given no coordinator handle. Every other session ignores this section.
- Trigger it the moment a separate agent seems useful, and before acting on that thought. Skip it for work you would finish in a handful of tool calls.
- Pass all four flags. `--context` decides most verdicts, so state file and subsystem overlap with the parent, whether the child is read-only, its dependencies, which workers are already live and what scope they own, and whether the parent alone may run or land the result.
- Append every verdict with `| tee >(jq -c . >> ~/.local/share/jev-delegation/decisions.jsonl)` so real decisions accumulate as line-delimited JSON for auditing, while the full verdict still prints for you to read.
- Branch on `decision` only. Never branch on `topology`, which is the raw model pick and disagrees with `decision` on exactly the borderline cases the gate catches. `policy_override` marks that disagreement.
- `FLAT` means do the work yourself and request nothing. Read `failed_gates`. Only a `coupling_risk` failure is worth one retry, and only after genuinely narrowing the child's scope.
- Any non-zero exit, unparseable output, or `failed_closed: true` means stay flat. Absence of an explicit `DELEGATE` is `FLAT`.
- **DEPTH RULE, the only line that changes when Orca's "Nested worker depth" moves from 1 to 2. At depth 1: on `DELEGATE`, a dispatched worker requests a worker from its coordinator via a non-blocking `orca orchestration send --type escalation` and keeps working meanwhile, never calling `worker-start` itself. At depth 2 this becomes: on `DELEGATE`, a dispatched worker may call `orca orchestration worker-start` itself.**
- The root coordinator is exempt from the depth rule. It is depth 0 and starts workers directly on `DELEGATE`.
- Every worker request must carry the four Jev probabilities and the proposed scope in its body, so the coordinator can decide without re-running the gate.
- Full protocol, including the escalation command template and the coordinator's deny criteria: `~/.local/share/jev-delegation/ORCHESTRATION-GATE.md`.
