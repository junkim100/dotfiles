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
- **On `DELEGATE`, attempt `orca orchestration worker-start`. If Orca refuses with `nested_worker_depth_exceeded`, request the worker from your coordinator instead with a non-blocking `orca orchestration send --type escalation`, and keep working meanwhile.**
- Never hardcode a depth. You cannot determine your own depth, and the refusal is the source of truth: it names both your depth and the current cap. This rule is therefore correct at any "Nested worker depth" setting, with nothing to edit when it changes.
- Ignore the refusal's own advice to complete the task in this terminal. Escalating to your coordinator keeps the work parallelizable; absorbing it yourself does not.
- The root coordinator sits at depth 0 and is never refused, so it starts workers directly on `DELEGATE`.
- Every worker request must carry the four Jev probabilities and the proposed scope in its body, so the coordinator can decide without re-running the gate.
- Full protocol, including the escalation command template and the coordinator's deny criteria: `~/.local/share/jev-delegation/ORCHESTRATION-GATE.md`.
