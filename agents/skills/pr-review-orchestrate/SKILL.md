---
name: pr-review-orchestrate
description: >
  Run the pr-review skill on one pull request as a supervised multi-worker pipeline: independent reviews by the harnesses and models the user picks, then a merge worker that starts only after every review has finished, then an audit worker that starts only after the merge has finished.
  Use when the user runs /pr-review-orchestrate, or asks to orchestrate a PR review with several workers or subagents (for example one Codex and one Claude Code reviewer).
argument-hint: "<PR number or URL> [reviewers=<harness>:<model>:<effort>,...] [merger=<harness>:<model>:<effort>] [auditor=<harness>:<model>:<effort>]"
---

# PR Review Orchestrate

This skill is the coordinator's playbook. It decides what each worker does and in which order; the orchestration skill the environment provides decides how workers are started, supervised, and released, and its own rules (delegation gates, message handling, release) apply unchanged. The coordinator reviews nothing itself.

```
review A ─┐
review B ─┼─▶ merge ─▶ audit ─▶ final review for the user
  ...    ─┘
```

With one reviewer there is no merge: review ─▶ audit.

## Arguments

- PR number or URL (required). A number uses the current repository.
- `reviewers=`: one entry per independent review, comma separated, each `<harness>:<model>:<effort>`. Default: `claude:claude-opus-5-5:xhigh,codex:gpt-6-astra:xhigh`.
- `merger=`: the worker that merges the reviews. Default: `claude:claude-opus-5-5:xhigh`.
- `auditor=`: the worker that audits the merged review. Default: `codex:gpt-6-astra:xhigh`. Prefer a different model family from the merger, so the final check is not done by the model that wrote the text.
- `harness` is `claude` (Claude Code) or `codex` (Codex); `model` and `effort` are passed through as the orchestration method expects them.
- The user may say it in words instead ("two Codex reviewers on gpt-6-astra, Claude Code merges"); map that onto these fields and print the result in the plan.

Choosing the number of reviewers: two (or more) for a large or risky PR, about 20+ changed files or 1000+ changed lines, or any change to a shared harness, provider, runtime, or launcher; one for a small PR. Different model families find different issues, so mix harnesses when two reviewers are used. In the blind comparison behind these defaults, the Claude Code reviews were short and precise and caught environment-level breaks by building the affected installs, while the Codex reviews covered more ground, mostly whether profile settings reach the request, with more low-value drafts; the two found almost disjoint sets of blockers. That is also why the default merger keeps the recommended set focused and the default auditor comes from the other family.

## Rules

1. Never post to GitHub or anywhere else, and never ask a worker to. The user posts.
2. Pin once, at the start: the PR head SHA and the base branch tip SHA. Every worker reviews that head and uses that tip for drift and integration checks. If the PR moves during the run, finish on the pinned head and say so; offer a new run on the new head.
3. Freeze the skill: copy the installed pr-review skill directory into the run directory before starting anyone, and point every worker at that copy, so an edit to the skill mid-run cannot make workers disagree.
4. Stage order is a hard dependency, not a timing guess:
   - Start the merge only after every reviewer has reported done and its folder holds `ledger/review.json` and `done.json`.
   - Start the audit only after the merger has reported done and its folder holds the same two files.
   - A worker's "almost done" message, a partial report, or a timeout is not done. The merge and the audit save their records more than once while they revise, so a stage that starts early reads an unfinished record.
5. Independence: reviewers never read each other's folders. The merger reads only the reviewers' folders. The auditor reads only the merger's and the reviewers' folders. Nobody reads earlier reviews of the same PR in the review ledger.
6. Failure: if a worker fails, read its reason, fix what is in the coordinator's power (a wrong path, a missing input), and restart it once. If a reviewer fails twice, continue with the reviews that finished: two or more go to the merge, one goes straight to the audit. If the merger or auditor fails twice, stop and give the user the best finished stage with what is missing.
7. While workers run, supervision is the coordinator's only job: answer questions, watch for done and failure, and do no review work of its own. Worker status messages arrive in the coordinator's session, so run it in a session the user is not typing in.

## Steps

1. Resolve the PR (`gh pr view`), pin head and base tip, and create the run directory `~/.local/state/pr-review/orchestrate/<owner>-<repo>-<N>-<head7>-<UTC stamp>/` with `skill/` (the frozen copy), `review-a/`, `review-b/` (one per reviewer), `merge/`, and `audit/`.
2. Print the plan: PR, pinned SHAs, each worker's harness, model, and effort, the stages, and the run directory. Then start; no confirmation is needed unless an argument was ambiguous.
3. Start every reviewer at once with the review brief.
4. When rule 4 allows, start the merger with the merge brief. With one reviewer, skip to step 5 and audit that review.
5. When rule 4 allows, start the auditor with the audit brief.
6. When the auditor is done, release every worker and show the user the audited review: the verdict, the recommended drafts with their `blocking` or `non-blocking` headers, the not-recommended list, and the path of the full report. Add one line per stage with its elapsed time, and any deviation the workers recorded in `done.json`.

## Worker briefs

Fill the placeholders: `{PR_URL}`, `{HEAD}`, `{BASE_TIP}`, `{RUN}` (run directory), `{WORK}` (this worker's folder), `{HARNESS}` (for example "Codex, gpt-6-astra, xhigh"), `{INPUTS}` (folders this worker may read). Every brief ends with the shared constraints block.

Review brief:

> Review {PR_URL} at head {HEAD} with the pr-review skill at {RUN}/skill (SKILL.md and every file it references; use that copy, not an installed one), exactly as it instructs, running in {HARNESS}. Use `report-dir={WORK}/ledger`. Materialize the pinned head in {WORK}/repo as the skill's Phase 0 describes (a shared clone of a local checkout when one exists), fetching exactly {HEAD} and {BASE_TIP}; use {BASE_TIP} as the target for every drift and integration check. Other reviewers are working in sibling folders of {RUN}; do not read them, and do not run `ledger.py find` or `outcomes`. Deliverables in {WORK}: `review.md` (exactly what you would print to the user), the report and ledger record under `{WORK}/ledger`, and `done.json` written last with `{"head", "elapsed_sec", "notes"}`, where notes lists every deviation from the skill or this brief.

Merge brief:

> Merge the finished reviews of {PR_URL} at head {HEAD} with the pr-review skill at {RUN}/skill in Merge mode, running in {HARNESS}: `merge={INPUTS as <folder>/ledger, comma separated}`, `report-dir={WORK}/ledger`. Read every input fully (review.md, ledger/report.md, ledger/review.json, done.json); these are the only other review outputs you may read. You may read their clones for code reading, but run probes only in your own checkout at {WORK}/repo, pinned as in the review brief. Deliverables as in the review brief; in `done.json` notes, also say which input contributed each recommended draft.

Audit brief:

> Audit the finished merged review of {PR_URL} at head {HEAD} with the pr-review skill at {RUN}/skill in Audit mode, running in {HARNESS}: `audit={RUN}/merge/ledger` (or the single review's ledger when there was no merge), `report-dir={WORK}/ledger`. Read the merged review and the reviews it merged ({INPUTS}); these are the only other review outputs you may read. Run probes only in your own checkout at {WORK}/repo, pinned as in the review brief. Deliverables as in the review brief, with the `Audit changes` section in `review.md`.

Shared constraints block:

> Read-only everywhere except {WORK}. Run tests and probes only inside {WORK} with a scratch environment (for Python, `uv venv` under {WORK}, `UV_CACHE_DIR={WORK}/uv-cache`, `TMPDIR={WORK}/tmp`); never use another checkout's environment, and never edit or create worktrees in the user's checkouts. Follow the repository hook's rules for running code (skip live tests; no paid model, sandbox, or cluster runs). Post nothing anywhere, never print secrets, and start no workers or subagents of your own. If a file-writing tool refuses a deliverable, write it with the shell. There is nobody to ask during the run: make the reasonable choice and record it in `done.json` notes. When the files exist, report done through the orchestration method with the path of `review.md`.
