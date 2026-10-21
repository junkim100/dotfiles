# Repo hook: wbl-eval

Applies when any changed path is under `eval/wbl-eval/` in the solar-system monorepo. House rules W1 to W4 apply too.

## Reading mandates

- `eval/wbl-eval/docs/GUIDELINE.md` is the review contract. The directory's `CLAUDE.md`/`AGENTS.md` requires reading it in full before reviewing a benchmark PR and stating in the review notes that you did; do that, in small chunks so nothing is truncated. Read it at `target_sha` (what the merged code must satisfy) and diff it against HEAD and `merge_base` for `convention_drift` (SKILL.md Phase 0.6). Policy that landed on the base after the PR branched (result-contract fields, error-handling rules, documentation requirements) binds the merged code; a PR that does not adopt it is an `integration` finding (L5).
- The eval wiki lookup is mandatory too: the clone lives at `eval/wbl-eval/eval-wiki` in a solar-system checkout (any Orca worktree under `~/orca/workspaces/solar-system/*/` or the main checkout). Start from `wiki/index.md`, open the pages for the benchmarks and subsystems the diff touches, follow their related links, and verify every load-bearing claim against code, registry files, or the original source; where the wiki and the code disagree, the code wins. The `wiki/repo/**` mirror describes the code at a later commit than an old PR head, so it can leak later fixes into a review of an earlier head; read code for anything about the reviewed revision. Cite the wiki pages you used in the report, never in a comment (house rule G2). If the clone is missing, say so.
- Item numbers drift as the guideline grows (the base contract moved from item 13 to item 15 in 2026). Confirm every number you cite against the copy you read.

## Review procedure: the guideline's own loop, in its order

The guideline's operating loop and its review-only checks are the backbone of a wbl-eval review (SKILL.md R13). Run them before the generic risk map and report them as the Guideline checklist.

1. **Pre-read.** Read `docs/GUIDELINE.md` in full at `target_sha` and record it as the first checklist row ("read in full at <sha>"). Diff it against HEAD and `merge_base` for drift.
2. **Item 0 first.** Before any implementation detail, check the complete changed-file list (from `git diff --name-status <merge_base> HEAD` in `WT`; `gh pr view --json files` stops at 100), including added files, renames, files outside the benchmark directory, and files inside copied upstream trees. Every file must serve the PR's stated scope.
3. **Build the checklist for this PR's type** from the table below, then run each item's *Verify* step as the guideline words it, separately for every execution path the PR adds (for example host Docker and E2B, a mirrored dataset and a local data directory): a benchmark that rejects missing input on the host path but turns the same failure into a 0.0 score inside the sandbox path violates item 15f. Record pass, violation, n/a, or not-checked with evidence for every row.
4. **Run the review-only checks.** The guideline's "Known gaps (not machine-enforced)" section lists checks `make param-check` does not do; run every one that applies (at the time of writing: item 0, items 25a to 25c, 25b's official-promotion evidence, 28's `migration.md` completeness, tier placement (25), experiment-file exhaustiveness (26), benchmark-arg order against sibling specs (16), canonical names (P6), base-contract items 15d to 15f, the static half of resume (27, P11), wbl-authored nested timeout keys, and a variant module that builds `info` by hand next to a conforming one (rule 25)). Re-read that section each time; it changes.
5. **Run the gate.** `make param-check` (inside `WT` with a scratch environment, R9) must print the literal success line. For mass registry or rename changes, check which verification-playbook proofs (Part C) the PR states and rerun the cheap ones (construct-all smoke, instance-attribute diff, failure-set diff).
6. **Check the PR body's proofs.** Operating-loop step 7 requires authors to state the file-scope check, required documentation and official-promotion evidence (items 0, 25a, 25b, 25c, 28), and the "scoring unchanged ≠ scores unchanged" distinction (P8) when generation plumbing moved. Missing proofs become one general PR comment that lists them, not one inline comment each.
7. **Documentation checks for every affected spec (25a to 25c).** For each new or changed YAML, including `.light` and archived variants affected through a shared benchmark, provider, judge, or harness: an exact overview row in `registry/evals/README.md`, a scoring row in the owning README's `오류 처리와 재시도` section, a retry row in the benchmark's `Retries, timeouts and resume` section, a YAML header note linking the overview row, links and anchors that resolve, and a retry note that matches the effective call paths. Trace the settings through the implementation; do not take the rows on trust.

| PR type | checklist items to run (besides 0 and the review-only checks) |
|---|---|
| New benchmark or migration | P5 and 21 (copied upstream identical, names mapped at the wrapper), P8 (router or port), 1 to 7 (registry authority, exhaustive null, no generation params in args, override buckets, full `parameters` forwarded), 8 and 9 (dataset through `dloaders`, private `bench-` mirror), 10 and 10a to 10d (result contract), 11 or 23, 12, 13 (shared E2B runtime), 14 (progress), 15a to 15g (base contract), 17 (judge profile), 19 (no dead args), 20 (determinism), 25, 25a to 25c, 25b when official, 26 for new experiment files, 27 (resume), 28 (`migration.md`) |
| New variant of an existing benchmark (`eval_v2.py`, a new spec version) | everything for a new benchmark that the variant touches, plus rule 25's variant gap (the variant's own `info` goes through `build_info()`), separate scoring and retry rows when behavior differs, and the official versioning rules when an official spec changes |
| Change to an existing benchmark | the items the diff touches, 25a to 25c for every affected spec, P8's statement when generation plumbing moved, official versioning and 25b for official setting changes |
| Shared harness, runtime, provider, or launcher | P9 and 15a to 15g for every benchmark that uses it, 16 and 22 for providers, 24 for profiles, the shared-change rule of 25c (follow every affected spec, update `src/wbl_eval/evals/benchmarks/README.md` for shared retry mechanisms), 26 for experiment files |
| Registry only (specs, profiles, experiments) | 1 to 4, 11, 12, 17, 18, 24, 25, 25a to 25c, 26, and the verification playbook for mass changes |
| Guideline, docs, or policy | provenance (SKILL.md L5), P7's rule that comments and docs are part of the contract, and house rule W4 |

## Mapping findings onto the guideline

Map a finding onto the guideline instead of arguing it from first principles, and cite the item both in the report and in the comment (house rule G2).

| what you found | lens | guideline |
|---|---|---|
| a generation param the wrapper hand-picks or drops on the way to the model | L2 | item 7 (forward the full `parameters`), item 1 |
| an unset profile value replaced by a wrapper or vendored default | L2 | P4 fallback decision tree (omitting is allowed only when the downstream default was read at its source), P4 "never duplicate a downstream default", item 5 |
| `null` reaching a request body, argv, env file, or generated config | L2 | P2 null contract, P10, rule 21 |
| `params.get(k, DEFAULT)` or `if "k" in params` on raw registry dicts | L2 | P2 forbidden patterns |
| a constructor default other than `None` while the code branches on `is None` and a spec sets it to `null` | L2 | P2 "If `None` is semantic, the ctor default must be `None`" (no lint catches it) |
| recorded metadata that differs from the value actually sent | L2 | P7 "comments and docs are part of the contract", item 10b (info carries effective values) |
| a declared arg nothing consumes, or consumption proven only at the first hop | L1 | P7, item 19 (grep the receiving side for the exact name) |
| a vendored tree that differs from its upstream pin, or renames inside it | L6 | P5, item 21 |
| a benchmark arg named like a generation param (`seed`, `timeout`, `temperature`) | L5 | P3 `benchmark_` prefix family, rule 7 |
| a timeout arg without a `_sec`/`_min`/`_ms` suffix | L5 | item 12, rule 20 |
| an inlined seed literal instead of `DEFAULT_SAMPLE_SEED` | L5 | P3, item 20, rule 8 |
| a dataset not loaded through `dloaders`, or not mirrored privately under the `bench-` prefix | L6 | items 8 and 9 (a 401 on the private mirror is the expected state; the question is whether the run environment has the token) |
| missing `total_samples`/`success_samples`, or `info` not built by `build_info()` | L5 | item 10, rule 23; item 10b, rule 25 |
| how errors are scored, a withheld headline, `main_score_basis`, retry budget | L4, L5 | items 10 and 10b (errors count at the metric's incorrect value unless `error_handling: upstream` selects the upstream rule; AA specs use `api_max_attempts: 30`; a completed result with `success_samples == 0` is valid; an upstream null stays null) |
| a repeated multi-metric result collapsed to `main_score`, a summary top-level key changed, a `sub_score` of another shape | L1, L3 | items 10a, 10c, 10d |
| a progress denominator that grows during the run, or progress output the watcher cannot parse | L4 | item 14 |
| base-contract drift (`limit`/`max_concurrency`/`log_path` not propagated, `os.environ` copies, per-call log kwargs, a per-provider `if/elif` instead of the shared resolver, system dependencies in shared build targets) | L1, L3 | P9, items 15a to 15g |
| a benchmark-side `if not records: return {...0...}`, or a zero invented for missing input | L4, L8 | P9 "empty input and exhausted failures are different cases", item 15f |
| judge or grader using the candidate's `parameters:` | L2 | item 17 |
| sandboxes created outside the shared runtime, so they lack attribution metadata | L7 | item 13 |
| provider HTTP client or timeout built by hand | L7 | item 16 |
| accidental or out-of-scope files | scope | item 0 |
| registry lifecycle change without documentation, official promotion without both API and vLLM sanity, a spec without an error-handling row, a new benchmark without `migration.md` | L5 | items 25a, 25b, 25c, 28 |
| resume declared without the full surface, or a resume knob as a ctor arg | L5 | P11, item 27 |
| a new registry file that is not written out in full | L5 | item 26 |

## CI semantics (Phase 5)

- `wbl-eval-param-lint` runs `make param-check`. Green proves spec shape (exhaustiveness, no generation params in `args:`, name collisions, base signatures, grouping and order, timeout suffixes). It proves nothing about whether a value reaches the model; that is L2.
- Success is the literal line `param-standardize: 위반 없음 ✅`, not merely exit 0.
- The lint skips vendored trees and dot-directories by design, so a finding inside `{bench}/src/**` is never lint-caught. That is L6.
- A new vendored tree must be excluded in four places: `[tool.ruff]` and `[tool.mypy]` excludes in `eval/wbl-eval/pyproject.toml`, the monorepo root `pyproject.toml` ruff exclude, and root `pants.toml` `pants_ignore`. The root ones are commonly missed because a bench-local `make lint` still passes.
- CI runs only for PRs whose base matches `on.pull_request.branches` in `.github/workflows/ci.yaml` (read it at `target_sha`); a stacked PR into any other branch gets no CI at all. GitHub runs it on the merge with the base, not on the head alone.
- Some contract tests are outside the CI test jobs (the guideline marks `tests/test_summary_contract.py` as not run by CI). Check the workflows' test selection, and run the contract tests the change touches in the merge candidate (Phase 5.4).

## Running code safely here

- Run tests and probes in `WT` with its own environment, never in the user's checkout. Some benchmark imports download data or models on import (the param lint imports every benchmark), which would otherwise land in a shared `.venv`.
- Live tests: pass `-k "not smoke"`, and deselect `*_integration.py` tests that start real evaluations (some start paid sandbox or model runs when credentials exist). Run suites in a credential-less tree.
- No paid model, sandbox, or cluster runs without the user's explicit approval.
