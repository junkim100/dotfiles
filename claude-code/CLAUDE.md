# No Hard-Wrapped Prose

**One logical line per paragraph, list item, or heading; never wrap prose at a column width.**

- Applies everywhere prose lives: markdown files, docstrings, code comments, YAML/config comments, commit message bodies.
- A newline is a semantic boundary (new paragraph, new list item, table row, code fence), never a cosmetic one.
- Code itself follows the language formatter (ruff line limits etc.); this rule governs natural-language text only.
- When editing an existing hard-wrapped file, reflow the paragraphs you touch; verify content is unchanged (whitespace-collapsed equality) when reflowing in bulk.

# No Em Dashes

**Never use em dashes (—) or en dashes (–) in prose.**

- Applies everywhere prose lives: chat responses, markdown files, docstrings, code comments, commit messages, PR descriptions.
- Rewrite instead: use a period for two separate thoughts, a colon before an explanation or list, a comma for a light aside, or parentheses for a true aside.
- Do not swap in a spaced hyphen ( - ) as a stand-in; restructure the sentence.
- Hyphens in compound words (well-known, end-to-end) and ranges written with a hyphen or "to" are fine.
- Leave verbatim quotes, cited text, and third-party content unchanged.

# Never Publish Claude Session Links

**Never include a Claude session or conversation link in anything you write.**

- Applies to PR descriptions, PR and issue comments, commit messages, code comments, docs, Slack messages, emails, and any other outward-facing text.
- Covers any URL that points at a Claude session or transcript, including claude.ai/code links, session share links, and cloud session URLs, as well as raw session IDs presented as a way to reach the conversation.
- The "Generated with Claude Code" attribution line and the Co-Authored-By trailer are fine, as long as they carry no session link.
- If the user explicitly asks for the session link in a specific place, share it there and nowhere else.

# Orca Delegation Gate

**Inside an Orca Run, run `jev-delegation` before creating or requesting any additional worker.**

- Applies in two roles only. You are a dispatched worker if your preamble names a coordinator terminal handle and a dispatch capability. You are the root coordinator if you drive an Orca Run and were given no coordinator handle. Every other session ignores this section.
- Trigger it the moment a separate agent seems useful, and before acting on that thought. Skip it for work you would finish in a handful of tool calls.
- Pass all four flags. `--context` decides most verdicts, so state file and subsystem overlap with the parent, whether the child is read-only, its dependencies, which workers are already live and what scope they own, and whether the parent alone may run or land the result.
- Append every verdict with `| tee >(jq -c . >> ~/.local/share/jev-delegation/decisions.jsonl)` so real decisions accumulate as line-delimited JSON for auditing, while the full verdict still prints for you to read.
- Branch on `decision` only. Never branch on `topology`, which is the raw model pick and disagrees with `decision` on exactly the borderline cases the gate catches. `policy_override` marks that disagreement.
- `FLAT` means do the work yourself and request nothing. Read `failed_gates`. Only a `coupling_risk` failure is worth one retry, and only after genuinely narrowing the child's scope.
- `UNAVAILABLE` means the gate could not run, not that delegating is unwise. Fall back to your own judgement, weighing the same things the gate weighs: independence from the parent's in-flight work, whether the coordination is worth it, and above all coupling. Say in your request that the gate was unavailable.
- Any non-zero exit, unparseable output, or `failed_closed: true` means stay flat. Those signal a real fault rather than an outage.
- **On `DELEGATE`, attempt `orca orchestration worker-start`. If Orca refuses with `nested_worker_depth_exceeded`, request the worker from your coordinator instead with a non-blocking `orca orchestration send --type escalation`, and keep working meanwhile.**
- Never hardcode a depth. You cannot determine your own depth, and the refusal is the source of truth: it names both your depth and the current cap. This rule is therefore correct at any "Nested worker depth" setting, with nothing to edit when it changes.
- Ignore the refusal's own advice to complete the task in this terminal. Escalating to your coordinator keeps the work parallelizable; absorbing it yourself does not.
- The root coordinator sits at depth 0 and is never refused, so it starts workers directly on `DELEGATE`.
- **Once you have dispatched anything, tending the mailbox is your only job until every worker settles.** Block on `orca orchestration check --terminal <you> --wait`, answer every question and escalation as it lands, and acknowledge each batch with `--ack` on the next wait. Do not start substantial work of your own while supervising: a worker blocked on an answer you never send will stall or invent a workaround you would not have approved.
- Never poll with a bare `check` you do not intend to process, because it marks the batch read and destroys the messages you were watching for. Use `--peek` to observe and `--all` for history. Polling the filesystem is the same mistake in disguise: it shows what a worker produced and nothing about what it needs.
- When a worker reports that something you own is blocking it, fix your thing rather than leaving it to route around the obstacle.
- Every worker request must carry the four Jev probabilities and the proposed scope in its body, so the coordinator can decide without re-running the gate.
- Full protocol, including the escalation command template and the coordinator's deny criteria: `~/.local/share/jev-delegation/ORCHESTRATION-GATE.md`.
