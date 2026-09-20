# Orca delegation gate

Canonical source for the jev-delegation gate. The compact operative rule is installed in `~/.claude/CLAUDE.md` for Claude workers and in Orca's Codex home `AGENTS.md` for Codex workers. Edit this file first, then re-sync those two copies.

## Applicability

This gate applies only inside an Orca Run, in one of two roles.

- **Dispatched worker**: your opening preamble names a coordinator terminal handle and a dispatch capability. You are at depth 1 or deeper.
- **Root coordinator**: you are driving an Orca Run and no coordinator handle was given to you. You are at depth 0.

Any other session ignores this gate entirely.

## When to run it

Run the gate the moment you catch yourself thinking that a separate agent would help, and before you create or request one.

Do not run it for work you would finish in a handful of tool calls. The gate is for candidates substantial enough to deserve their own terminal, and each call costs an API round trip.

Run it at most twice for the same candidate: once as conceived, and once more only if the first verdict was FLAT on `coupling_risk` and you have genuinely narrowed the child's scope in response.

## The call

Pass all four flags every time. Task names alone are not enough for a useful verdict.

`--context` is the field that most changes the outcome, because it carries the orchestration facts that cannot be inferred from a task name. Include whichever of these apply: which files or subsystems the parent is actively modifying, whether the child would be read-only, what the child depends on, which other workers are currently live and what scope they already own, whether any live worker would block waiting on this child's output, and whether the parent retains sole authority to run or land what the child produces.

```sh
jev-delegation \
  --parent-task "<what you are working on now>" \
  --proposed-task "<the specific candidate task>" \
  --reason "<why a separate worker looks useful>" \
  --context "<file overlap, dependencies, live workers, shared state, execution authority>" \
  | tee >(jq -c . >> ~/.local/share/jev-delegation/decisions.jsonl)
```

The `tee` is deliberate: it shows you the full verdict while appending one compact line per decision, building the corpus of real Orca decisions to audit later. Keep it. Without the `jq -c`, the log is pretty-printed JSON rather than valid line-delimited JSON.

## Reading the verdict

Branch on `decision` and nothing else.

Never branch on `topology`. That field is the model's raw pick, and it disagrees with `decision` exactly on the borderline cases this gate exists to catch. When the two disagree, `policy_override` is true. In testing, a task where root held sole execution authority scored 0.97 on delegate probability and was still correctly refused on coupling.

- **`decision: DELEGATE`**. See the depth rule below.
- **`decision: FLAT`**. Do the work yourself in this terminal, and do not request a worker. Read `failed_gates` to understand why. A `coupling_risk` failure is the one worth reacting to: narrowing the child to something read-only or non-overlapping may legitimately flip it.
- **Anything else**. A non-zero exit, unparseable output, or a body carrying `failed_closed: true` means stay flat and do the work yourself. The tool already fails closed by returning FLAT on error, so treat the absence of an explicit DELEGATE as FLAT.

## Depth rule

**Never hardcode a depth.** You cannot determine your own depth from inside a worker; you can only tell that you are one, from your preamble. Orca knows, and it tells you when it matters.

On DELEGATE, attempt `orca orchestration worker-start`. If Orca permits it, the dispatch proceeds. If Orca refuses, it returns the code `nested_worker_depth_exceeded` with a message naming both your depth and the current cap, and you then request the worker from your coordinator instead.

That makes this rule correct at any "Nested worker depth" setting, with nothing to edit when you change it. A refused attempt costs one cheap CLI call, and only on the rare dispatch path.

Orca's own next-steps text on that refusal tells you to complete the task in this terminal. Ignore that line. Escalating to your coordinator preserves the chance of parallel work; absorbing the task yourself forecloses it.

The root coordinator sits at depth 0 and is never refused, so it starts workers directly on a DELEGATE verdict.

## Requesting a worker after a depth refusal

When Orca refuses the dispatch, send the request with the escalation form from your own preamble, substituting your real handles. Escalation is deliberate rather than `ask`: it does not block, so you keep making progress on your own task while the coordinator decides. If the coordinator never answers, you simply finish the work yourself, which is the safe outcome.

```sh
orca orchestration send --from <your-terminal> --dispatch-capability <your-dcap> \
  --type escalation \
  --subject "Worker request: <short candidate name>" \
  --body "Requesting one additional worker. CANDIDATE: <proposed task>. SCOPE: <files and directories the child would own>. WHY SAFE: <independence and non-overlap argument>. JEV: decision=DELEGATE independent=<x> value=<x> coupling=<x> delegate_p=<x> failed_gates=none. I am continuing my own task meanwhile and will not start this child myself." \
  --task-id <your-task-id> --dispatch-id <your-dispatch-id>
```

Always include the four Jev probabilities in the body. The coordinator uses them to decide without re-running the gate, and they are what makes the decision auditable afterwards.

Use `orca orchestration ask` instead of escalation only when you genuinely cannot make any further progress without the answer.

## Coordinator side

Run the same gate before each `worker-start` you are about to issue, using the same four flags.

When an escalation arrives carrying a Jev result, trust the attached numbers rather than re-running the gate, unless the worker's stated scope conflicts with a scope you have already assigned to a live worker.

Deny the request when the proposed scope overlaps a live worker's files, when you are actively modifying the same subsystem, or when you would need to re-inspect the output before it counts as done. Those three patterns are what produced the rework rounds the thresholds were tuned on.
