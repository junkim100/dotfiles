---
name: pr
description: >
  Use when the user types /pr <N> or asks to review a GitHub pull request.
  Verification-first PR review: fetches the PR at its head SHA, checks every claim, reference, and feature-invariant against actually-pushed code (never the working tree, never the author's reply), classifies findings by severity with exact file:line anchors at head, prints a review, then drafts short, post-ready inline comments in the user's Korean style. However, the response to the user should be English. Does not post anything; the user posts comments himself.
---

# /pr — verification-first PR review

Reviews PR `<N>` (Phases 0–6), then drafts comments (Phase 7).
Pseudocode is normative. Follow steps in order. Take each branch literally.

## Hard rules (apply in every phase)
- R1. Ground truth is the PR head SHA, not the working tree. The repo is usually
  checked out on `main`; local files give base-branch line numbers and stale
  content. NEVER grep working-tree files for anchors or content.
- R2. Verify, do not trust. Check claims (PR body, commit messages, author
  replies) against fetched head code. A "success" run can hide per-instance
  crashes — confirm via the code/artifact, not the status.
- R3. Reason about net diff, not commit history.
- R4. Produce, do not post. Emit `{file, line, body}`; the user posts.
- R5. State each finding with an exact `file:line@HEAD` anchor and `path:line` evidence.
- R6. Verify it yourself; never outsource a check you can run. Before writing "please confirm X", ask whether a fetch, a diff, an HTTP probe, or importing the pure functions would answer it. Only ask the author for facts that exist solely in their head (intent, why a change was made). Anything that exists in code, in a registry, or on a public endpoint is yours to check.
- R7. A value that is dropped, defaulted, or rewritten between layers is a finding even when nothing crashes. Warnings, log lines, and comments do not neutralize it; they are how it hides.


## Schemas (handoff between phases)
```
FINDING = {
  id:        int,
  severity:  "High" | "Medium" | "Note" | "Nit",
  type:      "broken-reference" | "dead-code" | "contract-mismatch"
           | "fragile-invariant" | "churn-leftover" | "sibling-deviation"
           | "robustness" | "missing-test" | "silent-override"
           | "silent-failure" | "vendor-drift" | "external-dep" | "other",
  file:      str,            # repo-relative path
  line_at_head: int,         # anchor line in the head-SHA version of file
  problem:   str,            # what is wrong, concisely
  fix:       str | null,     # suggested change, optional
  evidence:  str             # "path:line" proving the claim
}
COMMENT = { file: str, line: int, body: str, style: "ko-formal" }
```

## Severity rubric (assign exactly one)
- High   = live regression / total-failure mode / broken reference that fails at runtime.
- Medium = latent fragility the feature itself depends on; contract mismatch; missing test for a load-bearing invariant.
- Note   = intended behavior worth conscious awareness (e.g. an override, a plan assumption).
- Nit    = cosmetic / dead-but-harmless / doc inconsistency.

---

## PHASE 0 — RESOLVE TARGET
```
0.1 PR ← integer from args. If absent → STOP, ask the user for a PR number.
0.2 META ← gh pr view PR --json \
      title,body,author,state,headRefName,baseRefName,additions,deletions,\
      changedFiles,headRefOid,mergeable,mergeStateStatus,commits
0.3 HEAD     ← META.headRefOid
    FILES    ← gh pr diff PR --name-only
    DIFF     ← gh pr diff PR
0.4 COMMITS  ← META.commits (oid[:9] + messageHeadline list)
0.5 churn_suspected ← (len(COMMITS) > 4)
                   OR any commit headline matches /merge|revert|remove|revert|되돌|제거|원복/
0.6 CONVENTIONS ← the repo's own review contract, if present. Look for docs/GUIDELINE.md (or CONTRIBUTING), and for a migration/knowledge log next to the changed code. Read the sections the diff touches (registry/params, data hosting, code convention, enforcement) and carry them as checklist items. The repo's own rules outrank your generic instincts, and citing a rule number makes a finding actionable. See "Repo hooks" below for repos with a known contract.
0.7 If the change adds or updates a vendored upstream tree, record the pin (commit SHA / tag) that its docs or pyproject claim. Phase 2.5 checks it.
```

## Repo hooks (repo-specific contracts this skill knows about)

### wbl-eval (`eval/wbl-eval/**` in the solar-system monorepo)

If any changed path is under `eval/wbl-eval`, `eval/wbl-eval/docs/GUIDELINE.md` is the review contract. Read it in Phase 0.6 and cite it by item/rule number in findings and comments, e.g. "GUIDELINE item 7". A cited rule turns a matter of taste into a matter of policy, and the author can act on it without debate.

Map findings onto the guideline instead of arguing them from first principles:

| what you found | cite |
|---|---|
| a generation param the wrapper hand-picks or drops on the way to the model | item 7 (forward the full `parameters`, never a few CLI flags), P10 |
| an unset profile value replaced by a wrapper or vendored default | P4 decision tree (case 3 "omit" is allowed only when the downstream default was actually read at its source) and P4's "never duplicate a downstream default into the wrapper", item 5 |
| `null` reaching a request body, env file, or generated config | P2 null contract, P10, rule 21 |
| `params.get(k, DEFAULT)` or `if "k" in params` on raw registry dicts | P2 (null swallows the default) |
| a ctor default that is not `None` while the code branches on `is None` | P2's terminal_bench detector (default ≠ None ∧ `is None` branch ∧ spec null ⇒ bug) |
| a declared spec arg nothing consumes, or consumption proven only at the first hop | P7 and item 19 (grep the receiving side for the exact name) |
| a vendored tree that differs from its upstream pin | P5 and item 21 |
| a benchmark arg named like a generation param (`seed`, `timeout`, `temperature`) | P3's `benchmark_` prefix family, rule 7 |
| a timeout arg without a `_sec`/`_min`/`_ms` suffix | item 12, rule 20 |
| an inlined seed literal instead of `DEFAULT_SAMPLE_SEED` | P3, rule 8 |
| dataset not loaded through dloaders, or not mirrored to the private Upstage HF space | items 8 and 9 (a 401 on the mirror is the *expected* private state; the real question is whether the run env has the token) |
| missing `total_samples` / `success_samples` in result info | item 10, rule 23 |
| a progress denominator that grows during the run | item 14 (true total from the first line) |
| base-contract drift (`limit`/`max_concurrency`/`log_path` not propagated, `os.environ` copy, per-call log kwargs, provider if/elif instead of the shared resolver) | P9 and items 13a-13g |
| a benchmark-side `if not records: return {...0...}` | P9, item 13f |

CI semantics for this repo (Phase 5):
- `wbl-eval-param-lint` runs `make param-check`. Green proves spec SHAPE (exhaustiveness, no generation params in `args:`, name collisions, base signatures, grouping/order, timeout suffixes). It proves nothing about whether a value reaches the model, which is why Phase 2.4 exists.
- Part C's own warning applies to you too: success is the literal line `param-standardize: 위반 없음 ✅`, not merely exit 0.
- The lint's scan skips vendored trees and dot-directories by design, so a finding inside `{bench}/src/**` will never be lint-caught. That is Phase 2.5's job.
- A new vendored tree must be excluded in four places (both `[tool.ruff]`/`[tool.mypy]` excludes in `eval/wbl-eval/pyproject.toml`, the monorepo root `pyproject.toml` ruff exclude, and root `pants.toml` `pants_ignore`); the root one is the commonly missed one because a bench-local `make lint` still passes without it.

## PHASE 1 — GROUND TRUTH HELPERS
```
1.1 Define (do NOT read working-tree copies of these files):
      fileAtHead(F) :=
        gh api repos/:owner/:repo/contents/F?ref=HEAD -q .content | base64 -d
1.1b Shell gotcha: in zsh, `git show "$SHA:eval/x.py"` silently applies the `:e` modifier and mangles the path. Write `git show "${SHA}:eval/x.py"`, or paste the literal SHA.
1.2 For any anchor/line-number/symbol lookup in a changed file, operate on
    fileAtHead(F). For repo-wide "is X defined/consumed anywhere" lookups,
    grep the working tree ONLY to locate definitions (line numbers there are
    advisory); confirm the consuming/defining line exists at HEAD if it is in a
    changed file.
```

## PHASE 2 — VERIFY CLAIMS & REFERENCES
```
For every NEW symbol, attribute, config key, or env var the DIFF introduces or reads:
  2.1 Locate its definition and its consumer.
      BRANCH:
        not defined / not consumed anywhere it must be
            → FINDING(High, broken-reference, evidence=where it should have been)
        found → continue
      (Watch attribute aliasing: e.g. a field named `input_schema` with
       alias `inputSchema`; an env var that another module must read.)

For every VALUE the DIFF sets (timeout, default, flag, resource spec):
  2.2 Trace how it is actually consumed.
      BRANCH:
        overwritten / ignored before first use
            → FINDING(Nit, dead-code, problem="overwritten at <evidence>; harmless but misleading")
        forced (e.g. {**os.environ, **forced}) while docs/comment call it optional/overridable
            → FINDING(Medium, contract-mismatch)
        duplicated literal in 2+ places that must stay equal
            → FINDING(Nit, dead-code/other, fix="hoist to one constant")

2.4 ARGUMENT-FLOW TRACE (run this whenever the change adds or edits a benchmark/job/config wrapper).
    Every knob has two chains. Walk both end to end and write down what each hop does to the value.
      config chain:  registry/spec file → loader (what does it pop, strip, or rename?) → constructor → CLI flags / config file the child reads → the consuming code
      model chain:   profile parameters → shared resolver → the file or env the child reads → the client object → the actual request payload
    At each hop classify the value: passed | renamed | dropped | defaulted | rewritten | overwritten.
      BRANCH:
        dropped or defaulted with only a log/comment as the guard
            → FINDING(Medium, silent-override, problem="<key> never reaches the model/harness; the effective value is <x>", fix="record the effective value in result info, or fail fast")
        an UNSET value becomes an explicit non-provider default on the wire (e.g. a vendored dataclass default temperature/max_tokens)
            → FINDING(Medium, silent-override). This is the most missed class: null means "use the default", but which layer's default?
        renamed or rewritten (provider remap, model_name override, list truncated to first element)
            → OK if documented at the site; FINDING(Note) if not
        a declared spec key that no code path consumes
            → FINDING(Nit, dead-code) if inert, FINDING(Medium) if it would silently mis-size or mis-route work
    Also check the reverse direction: a vendored default that LOOKS like it shadows the wrapper (e.g. `setdefault("max_tokens", 16384)`). Grep every read of that field before flagging; a default nobody reads is dead, not an override.

2.5 VENDORED FIDELITY (whenever `<component>/src` or a vendor/ tree is added or touched).
    Fetch the claimed pin and diff it, do not trust the PR body:
      curl -sL https://github.com/<org>/<repo>/archive/<pin>.tar.gz | tar xz -C /tmp/up --strip-components=1
      diff -r --brief /tmp/up <vendored dir>
      BRANCH:
        any file differs
            → FINDING(Medium, vendor-drift). Ask WHY the upstream edit was needed (that is the one thing only the author knows), and check every doc that asserts byte-identity.
        differs only by "Only in upstream" for assets/docs/large archives
            → OK, but note anything the runtime needs that is NOT vendored (see 4.4).

For every INVARIANT the feature depends on (pairing, name-match, ordering,
two code paths that must agree):
  2.3 Identify the 2+ sites that must agree and HOW each derives its value.
      BRANCH:
        sites derive from different sources OR different resolution depth/logic
            → FINDING(Medium+, fragile-invariant,
                      problem="A uses <x>, B uses <y>; they agree only for the tested case",
                      fix="derive both from one source / one function")
        sites agree by construction (same source, same function) → OK (no finding)
```

## PHASE 3 — CHURN & SIBLING CHECKS
```
3.1 if churn_suspected:
      grep DIFF for keywords of any feature added-then-removed in COMMITS
      (model names, deleted modules, temp flags).
      BRANCH:
        leftover reference remains in net DIFF
            → FINDING(Nit/Medium by impact, churn-leftover)
        net DIFF clean → OK
3.2 if the change mirrors an existing pattern (sibling language config, sibling
    benchmark, parallel module):
      diff the new block against the sibling.
      BRANCH:
        structural deviation not explained by the change's intent
            → FINDING(Medium/Note, sibling-deviation)
        only intended fields differ → OK
```

## PHASE 4 — ROBUSTNESS LENS
```
4.1 For new error-handling / concurrency / external-call code:
      check for:
        - fail-fast where best-effort is expected
          (e.g. asyncio.gather default return_exceptions=False on an optional step
           whose failure aborts the whole run)            → FINDING(High, robustness)
        - silent failure (catch → pass / swallow)         → FINDING(Medium, robustness)
          EXCEPTION: in wbl-eval benchmark runners, catch→break→score=False on an
          API error is intended; do NOT flag that.
        - unbounded concurrency / missing timeout         → FINDING(Medium, robustness)
4.1b SILENT-FAILURE TAXONOMY. Beyond catch→pass, flag these shapes:
      - warn-and-continue on a value that changes the measurement (log line is not a guard) → FINDING(Medium, silent-failure)
      - an existence gate that passes on a partial artifact ("if dir exists and is non-empty: return") → check whether the WRITER is atomic; atomic writer = OK, direct write = FINDING(Medium)
      - a fallback that downgrades to a permissive default when input is missing (None → True, "" → "not-needed", missing timestamp → "always in window") → trace what the missing input actually is in production. If it is missing ALWAYS, the guard never engages → FINDING(Medium, silent-failure)
      - an all-failed run that still produces a publishable number → only a finding if the repo lacks a gate for it; check the repo's own contract first (0.6) before inventing one

4.3 VERIFY BY EXECUTION (do this before writing any "please check" comment).
    Pure logic can be exercised without the cluster, the GPUs, or a paid API:
      - copy the changed module at HEAD into a scratch dir, stub only the heavy imports (base classes, resolvers), keep the real helper modules
      - drive the aggregation / limit / sampling / resume-filter functions with synthetic inputs, including the degenerate cases (empty dir, truncated JSON, stale leftovers, error-only records)
      - reproduce third-party library behavior in a throwaway venv (`uv venv` + the pinned version) rather than reasoning from memory about what a library does
      BRANCH:
        a function misbehaves → FINDING with the reproducing input in the evidence, which makes the comment undeniable
        everything passes → do NOT write the "add tests / please verify" comment for that area; say so in the report instead

4.4 EXTERNAL DEPENDENCY EXISTENCE (datasets, images, mirrors, endpoints the change introduces).
    These are cheap HTTP probes, so run them:
      - HF dataset/model: `curl -s -o /dev/null -w "%{http_code}" https://huggingface.co/api/datasets/<repo>`; 200 = public, 401 = private or nonexistent (anonymous cannot tell them apart)
      - HF configs/splits actually match the code's constants: `https://datasets-server.huggingface.co/splits?dataset=<repo>`, and `/rows?...` to check column names and row shapes against the parsing code
      - container image: registry v2 anonymous token → manifest → config blob, which also reveals the real listen port, CMD, and env
      BRANCH:
        the code's constants disagree with the live schema → FINDING(High, broken-reference)
        the resource is missing or private AND is the only source at runtime
            → decide by who can act: if the reviewer's own org must publish it, that is an ops task for the user, not a PR comment. Report it in the summary, not as a comment the author cannot resolve.
        a needed artifact is gitignored and thus absent from a fresh checkout (`*.zip`, weights, seeds) → verify the fallback path exists and fails loudly, then report as above

4.2 Does a test cover the load-bearing invariant from 2.3?
      BRANCH:
        no test references the new functions / invariant
            → FINDING(Low-Med→Medium, missing-test)
        covered → OK
```

## PHASE 5 — CI
```
5.1 CHECKS ← gh pr checks PR
5.2 Record each check pass/fail. A failing required check is itself High.
5.3 Read the check LIST, not just the verdicts. "skipping" is not "passing": a path filter may have excluded the very tests that cover this change. If a suite that looks relevant was skipped, say which one and why (usually a detect-changes path filter).
5.4 Know what a green check does NOT prove:
      - a param/registry lint proves the spec's SHAPE (exhaustive keys, null-vs-value, signature match), never that the values are semantically right or that they reach the model
      - a lint/type job that passes because the new tree was added to an exclude list proves only that the exclusion works. Check that the exclusion was added in EVERY place the repo requires (root and sub-project configs, build-system ignores) and that nothing outside the vendor tree got excluded along with it.
      - a large-file/LFS check proves size limits, not that committed data BELONGS in the repo. For added data files, ask: is it upstream's own tracked content, does any code read it, and does it duplicate the runtime source (a dataset on a hub)? Divergent duplicate data is a provenance finding, not a size finding.
      - unit tests passing says nothing about a benchmark's numbers; those live in Phase 4.3.
```

## PHASE 6 — EMIT REVIEW (post nothing)
```
6.1 Print, in this order:
      - One-line verdict (mergeable? what blocks?).
      - What was verified (the checks you actually ran, so the user trusts the result). List the Phase 4.3/4.4 runs explicitly with their outcome, including the areas that came back CLEAN. A cleared area is a review result, and it is what justifies not commenting there.
      - Findings table: severity | file:line@HEAD | problem | fix.
      - CI status + mergeable/mergeStateStatus.
6.2 Lead with High/Medium. Separate Note/Nit.
6.3 Proceed to PHASE 7 and draft comments for the High/Medium findings (no need to ask).
```

## PHASE 7 — DRAFT COMMENTS (always, after Phase 6)
```
7.0 Comment-worthiness filter. Drop a finding from the comment set when:
      - you verified the code is correct (4.3) and the only residue was your own doubt
      - the author cannot act on it (an artifact only the reviewer's org can publish, infrastructure access) → move it to the summary as an ops note
      - it merely restates a repo convention the code already follows (check 0.6 before claiming a deviation)
    Keep it when the fix is in the author's hands, even if it is a Nit. Order the emitted comments by severity so the user can cut the tail.
7.1 For each FINDING to comment:
      re-run fileAtHead(file) and confirm line_at_head still points at the
      intended code (anchor may have moved if the PR was updated). Update line.
7.2 Compose body in STYLE = ko-formal, SHORT & SIMPLE:
      - Keep it to 1–2 sentences. No preamble, no restating the code, no hedging.
      - State the problem; add the fix only if it is not obvious from the problem.
      - Korean with 입니다/습니다 endings.
      - English (Latin) for all technical/computing terms (timeout, env, default,
        override, regex, semaphore, ...). Hangul only for native grammar/words.
      - No Korean gloss in parens after an English term.
      - Reference cross-file evidence as `path:line`.
7.3 Emit each as: file · Line N · body.  (one block per comment)
7.4 The user posts them. Do NOT call gh to post.
```

## Notes for the operator (you)
- N1. If the working tree shows different content than fileAtHead, trust fileAtHead (R1) and say so.
- N2. The user lands out-of-band fixes on related PRs without mentioning them; if a premise looks already-fixed, re-check git/PR state before reporting it as broken.
- N3. Distinguish "looks like a bug" from "dead / overwritten / intended." Trace before flagging.
- N4. Two findings per review are worth more than twenty. The scarce resource is the author's attention, so spend Phase 4.3 turning maybes into certainties and drop the rest.
- N5. When the user asks a follow-up question about the change ("does anything override X?", "is Y normal?"), treat it as a missing phase, not a one-off answer: run the trace, then fold the result back into the finding set and the comment list.
- N6. "Is this normal?" is answered with repo data, not taste: rank the thing against its siblings (file sizes, directory layouts, sibling specs) and quote the distribution.
