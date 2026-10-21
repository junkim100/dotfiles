# Repo hook: wbl-eval

Applies when any changed path is under `eval/wbl-eval/` in the solar-system monorepo. House rules W1 to W4 apply too.

## Reading mandates

- `eval/wbl-eval/docs/GUIDELINE.md` is the review contract. The directory's `CLAUDE.md`/`AGENTS.md` requires reading it in full before reviewing a benchmark PR and stating in the review notes that you did; do that, in small chunks so nothing is truncated. Read it at `target_sha` (what the merged code must satisfy) and diff it against HEAD and `merge_base` for `convention_drift` (SKILL.md Phase 0.6). Policy that landed on the base after the PR branched (result-contract fields, error-handling rules, documentation requirements) binds the merged code; a PR that does not adopt it is an `integration` finding (L5).
- The eval wiki lookup is mandatory too: the clone lives at `eval/wbl-eval/eval-wiki` in a solar-system checkout (any Orca worktree under `~/orca/workspaces/solar-system/*/` or the main checkout). Start from `wiki/index.md`, open the pages for the benchmarks and subsystems the diff touches, follow their related links, and verify every load-bearing claim against code, registry files, or the original source; where the wiki and the code disagree, the code wins. The `wiki/repo/**` mirror describes the code at a later commit than an old PR head, so it can leak later fixes into a review of an earlier head; read code for anything about the reviewed revision. Cite the wiki pages you used in the report, never in a comment (house rule G2). If the clone is missing, say so.
- Item numbers drift as the guideline grows (the base contract moved from item 13 to item 15 in 2026). Confirm every number you cite against the copy you read.

## Mapping findings onto the guideline

Map a finding onto the guideline instead of arguing it from first principles. Cite the number in the report; in a comment only when the rule is the argument (G2).

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
