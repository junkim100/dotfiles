---
name: pr
description: >
  Use when the user types /pr <N> or asks to review a GitHub pull request.
  Verification-first, multi-agent PR review: materializes the PR head SHA in a git worktree, fans out independent finder lenses over it, puts every candidate through an adversarial verifier that never saw the finder's reasoning, sweeps for gaps, then prints a review and drafts short, post-ready inline comments in the user's Korean style. The response to the user should be English. Does not post anything; the user posts comments himself.
---

# /pr: verification-first, fan-out PR review

Reviews PR `<N>` in Phases 0-6, then drafts comments in Phase 7.
Pseudocode is normative. Follow steps in order. Take each branch literally.

Topology: **materialize head → fan out lenses → adversarially verify every candidate → sweep for gaps → report → draft comments**.

Find for recall, report for precision, comment for certainty. Those are three different bars, and Phase 3 is the machinery that separates them. A finder that suppresses a half-believed candidate has bypassed the verifier, which is the dominant cause of misses. A comment drafted from an unverified candidate spends the author's attention on your doubt.

## Hard rules (apply in every phase, and go in every subagent prompt)

- R1. Ground truth is `WT`, a worktree checked out at the PR head SHA (Phase 0.7). The primary working directory is usually on `main`: it gives base-branch line numbers and stale content. Never read, grep, or anchor against it. Every subagent receives `WT` and the same instruction.
- R2. Verify, do not trust. Check claims (PR body, commit messages, author replies, CI verdicts) against code at `WT`. A green run can hide per-instance crashes: confirm via the code or the artifact, not the status.
- R3. Reason about net diff, not commit history.
- R4. Produce, do not post. Emit `{file, line, body}`; the user posts. No subagent posts, edits, pushes, or comments.
- R5. State each finding with an exact `file:line@HEAD` anchor and `path:line` evidence.
- R6. Never outsource a check to the **author**. Before writing "please confirm X", ask whether a read, a diff, an HTTP probe, or importing the pure functions would answer it. Only ask the author for facts that exist solely in their head: intent, and why a change was made. Anything in code, in a registry, or on a public endpoint is yours to check. Delegating that check to a subagent is still you checking it.
- R7. A value that is dropped, defaulted, or rewritten between layers is a finding even when nothing crashes. Warnings, log lines, and comments do not neutralize it; they are how it hides.
- R8. No silent caps. Whenever you bound the work (a lens not run, candidates dropped before verify, a changed file no lens opened, a probe that failed), say so in the report. A review that quietly narrowed its scope reads to the user as full coverage.
- R9. Subagents find and verify. They never edit files, never post, never run destructive or state-changing commands, and never `git commit`/`push`. They return their schema and nothing else.

## Schemas (handoff between phases)

```
BRIEF = {                      # built once in Phase 1, pasted into every finder prompt
  pr, head, wt,                # PR number, head SHA, worktree path
  title, body_claims: str[],   # claims the PR body makes, each independently checkable
  files: str[],                # changed paths
  commits: str[],              # oid[:9] + headline
  churn_suspected: bool,
  conventions: str[],          # rules from 0.6, quoted, with their id/number
  vendor_pins: {dir, repo, pin}[]
}

FINDER_RESULT = {
  lens:       str,             # "L1".."L8"
  candidates: CANDIDATE[],
  files_read: str[],           # every changed file this lens actually opened
  cleared:    str[],           # checks run that came back clean, one line each
  blocked:    str[]            # checks that could NOT be run, and why (feeds R8)
}

CANDIDATE = {
  lens:      str,
  file:      str,              # repo-relative
  line:      int,              # line in WT, i.e. at HEAD
  claim:     str,              # what is wrong, one sentence
  failure:   str,              # the concrete scenario: inputs/state -> wrong outcome
  evidence:  str,              # "path:line" (+ quoted line) proving it
  severity:  "High" | "Medium" | "Note" | "Nit",
  type:      str               # see FINDING.type
}

VERDICT = {
  state:     "CONFIRMED" | "PLAUSIBLE" | "REFUTED",
  quote:     str,              # the line that proves the verdict, either way
  reason:    str,              # for CONFIRMED: the triggering inputs/state.
                               # for PLAUSIBLE: what would confirm it.
                               # for REFUTED: what makes the claim factually wrong.
  method:    "executed" | "read"   # executed outranks read; see 3.4
}

FINDING = {
  id:        int,
  severity:  "High" | "Medium" | "Note" | "Nit",
  type:      "broken-reference" | "dead-code" | "contract-mismatch"
           | "fragile-invariant" | "churn-leftover" | "sibling-deviation"
           | "robustness" | "missing-test" | "silent-override"
           | "silent-failure" | "vendor-drift" | "external-dep" | "other",
  file:      str,
  line_at_head: int,
  problem:   str,
  fix:       str | null,
  evidence:  str,
  verdict:   VERDICT
}

COMMENT = { file: str, line: int, body: str, style: "ko-formal" }
```

## Severity rubric (assign exactly one)

- High   = live regression / total-failure mode / broken reference that fails at runtime.
- Medium = latent fragility the feature itself depends on; contract mismatch; missing test for a load-bearing invariant.
- Note   = intended behavior worth conscious awareness (an override, a plan assumption).
- Nit    = cosmetic / dead-but-harmless / doc inconsistency.

## Orchestration contract

- Dispatch finders with the `Agent` tool. Put every lens of a wave in **one message** so they run concurrently.
- Each subagent prompt contains: the hard rules above, `BRIEF`, its own lens body verbatim, its return schema, and "return the JSON only, no prose".
- Subagents are blind to each other. Never paste one lens's candidates into another lens's prompt. If two lenses flag the same line for different reasons, keep both and let dedup handle it in 3.1.
- **Fallback**: if the `Agent` tool is not in your tool set, do not error. Run every selected lens yourself, sequentially, in this context, then verify each candidate yourself with a deliberate adversarial re-read. Say plainly in the Phase 6 report that this was a single-context run without fan-out, so the user is not misled about what ran.
- Scale by applicability, not by diff size. Three lenses on a small PR is the correct fleet, not a shortfall.

---

## PHASE 0: RESOLVE TARGET & MATERIALIZE HEAD

```
0.1 PR ← integer from args. If absent → STOP, ask the user for a PR number.
0.2 META ← gh pr view PR --json \
      title,body,author,state,headRefName,baseRefName,additions,deletions,\
      changedFiles,headRefOid,mergeable,mergeStateStatus,commits
0.3 HEAD  ← META.headRefOid
    FILES ← gh pr diff PR --name-only
    DIFF  ← gh pr diff PR
0.4 COMMITS ← META.commits (oid[:9] + messageHeadline list)
0.5 churn_suspected ← (len(COMMITS) > 4)
                   OR any commit headline matches /merge|revert|remove|되돌|제거|원복/

0.6 CONVENTIONS ← the repo's own review contract, if present. Look for docs/GUIDELINE.md
    (or CONTRIBUTING), and for a migration/knowledge log next to the changed code. Read the
    sections the diff touches (registry/params, data hosting, code convention, enforcement)
    and carry them as quoted checklist items with their rule numbers. The repo's own rules
    outrank your generic instincts, and citing a rule number makes a finding actionable.
    See "Repo hooks" for repos with a known contract.

0.7 MATERIALIZE. This is what makes fan-out safe: subagents get real files with real
    HEAD line numbers instead of gh-api reads or a stale main checkout.
      WT ← <scratchpad>/pr-<PR>-<HEAD[:7]>
      git fetch origin pull/<PR>/head
      git worktree add --detach "$WT" FETCH_HEAD
      git -C "$WT" rev-parse HEAD          # MUST equal HEAD; if not, the PR moved, so refetch
    BRANCH:
      worktree add fails (repo too large, no space, shallow clone)
          → DEGRADED MODE (below): run the lenses yourself sequentially rather than
            fanning out, and record the degradation (R8)
      succeeds → every read, grep, and anchor from here on is against WT
    Clean up at the very end of Phase 7: git worktree remove --force "$WT"
    Do NOT clean up earlier. Phase 7.1 re-anchors against WT, and the user's follow-up
    questions (N5) are answered there too.

0.8 If the change adds or updates a vendored upstream tree, record the pin (commit SHA or
    tag) that its docs or pyproject claim. Lens L6 checks it.
```

### Degraded mode (only when 0.7 fails)

Without a worktree there are no real files to hand a subagent, so fan-out is off and you read the head SHA one file at a time:

```
fileAtHead(F) := gh api repos/:owner/:repo/contents/F?ref=HEAD -q .content | base64 -d
```

- Use `fileAtHead(F)` for every anchor, line number, and symbol lookup in a changed file.
- For repo-wide "is X defined or consumed anywhere" questions, grep the primary working tree **only to locate** definitions. Line numbers there are advisory. If the hit is in a changed file, confirm the line exists at HEAD with `fileAtHead`.
- zsh gotcha: `git show "$SHA:eval/x.py"` silently applies the `:e` history modifier and mangles the path. Write `git show "${SHA}:eval/x.py"`, or paste the literal SHA.
- Say in the Phase 6 report that the review ran degraded, and which lenses that cost you (L6 and L8 in particular need real files on disk).

## PHASE 1: BRIEF & LENS SELECTION

```
1.1 Read the diff yourself, once, end to end. You are not looking for bugs here; you are
    building the map the fleet works from. Note: what each file is for, which layers the
    change crosses, and which of the lenses below have anything to bite on.

1.2 body_claims ← decompose the PR body into individually checkable assertions
    ("vendored at pin X", "params are forwarded", "matches the sibling benchmark",
    "dataset is mirrored"). Each one is a claim some lens must land on. A claim no lens
    covers is a gap you own, not the author's.

1.3 Assemble BRIEF. This is the only context finders get about the PR, so it must stand
    alone: a finder cannot ask you a follow-up question.

1.4 SELECT LENSES.
      always:        L1 (reference integrity)
                     L3 (invariant pairing)
                     L4 (silent failure & robustness)
      if the change adds or edits a wrapper, runner, registry/config spec, job launcher,
      or anything that carries a value from a config file toward a process or a request:
                     L2 (argument-flow trace)          ← the highest-yield lens; run it
                                                          whenever it plausibly applies
      if CONVENTIONS is non-empty:
                     L5 (repo-contract conformance)
      if a vendor tree, dataset, container image, endpoint, or pin is added or touched:
                     L6 (vendored fidelity & external deps)
      if churn_suspected, or the change mirrors an existing sibling:
                     L7 (churn & sibling deviation)
      if the diff contains logic that runs without a cluster, GPU, or paid API
      (aggregation, limit/sampling, resume filters, parsing, scoring, path building):
                     L8 (execution proof)

1.5 Print the selected fleet to the user in one line before dispatching, with the lenses
    you skipped and why (R8). Then dispatch Phase 2.
```

## PHASE 2: FINDER FAN-OUT

Dispatch every selected lens in one message. Each returns `FINDER_RESULT`.

Prepend to every lens prompt:

> You are a finder in a PR review fleet. Ground truth is the worktree at `{wt}`, checked out at the PR head SHA. Never read or grep outside it for anchors or content. Do not edit anything, do not post anything, do not run state-changing commands. Return the JSON schema only.
>
> Surface every candidate you can name a concrete failure scenario for, including ones you only half-believe. A separate adversarial verifier judges each candidate afterwards, and it never sees your reasoning. Dropping a half-believed candidate bypasses that verifier and is the single largest cause of missed bugs. Do **not** pad: a candidate with no nameable failure scenario is not a candidate.
>
> Prove by running the code wherever you can rather than reasoning about it. Anything you could not check, put in `blocked` with the reason. Anything you checked and found clean, put in `cleared` as one line.

### L1: Reference integrity

For every new symbol, attribute, config key, or env var the diff introduces or reads, locate both its definition and its consumer.

- not defined, or not consumed anywhere it must be → `High`, `broken-reference`, evidence = where it should have been.
- Watch attribute aliasing: a field named `input_schema` with alias `inputSchema`; an env var another module must read; a key written in snake_case and read in camelCase.
- For each **value** the diff sets (timeout, default, flag, resource spec), trace how it is actually consumed:
  - overwritten or ignored before first use → `Nit`, `dead-code`, "overwritten at `<evidence>`; harmless but misleading"
  - forced (`{**os.environ, **forced}`) while docs or comments call it optional or overridable → `Medium`, `contract-mismatch`
  - the same literal duplicated in 2+ places that must stay equal → `Nit`, fix = "hoist to one constant"

### L2: Argument-flow trace

Every knob has two chains. Walk both end to end and record what each hop does to the value.

- config chain: registry/spec file → loader (what does it pop, strip, or rename?) → constructor → CLI flags or config file the child reads → the consuming code
- model chain: profile parameters → shared resolver → the file or env the child reads → the client object → the actual request payload

At each hop classify the value as `passed | renamed | dropped | defaulted | rewritten | overwritten`.

- dropped or defaulted with only a log line or comment as the guard → `Medium`, `silent-override`, claim = "`<key>` never reaches the model/harness; the effective value is `<x>`", fix = "record the effective value in result info, or fail fast"
- an **unset** value becoming an explicit non-provider default on the wire (a vendored dataclass default temperature/max_tokens) → `Medium`, `silent-override`. This is the most-missed class in this repo family: null means "use the default", but which layer's default?
- renamed or rewritten (provider remap, model_name override, a list truncated to its first element) → OK if documented at the site; `Note` if not
- a declared spec key no code path consumes → `Nit`, `dead-code` if inert; `Medium` if it would silently mis-size or mis-route work

Check the reverse direction too: a vendored default that *looks* like it shadows the wrapper (`setdefault("max_tokens", 16384)`). Grep every read of that field before flagging. A default nobody reads is dead, not an override.

### L3: Invariant pairing

For every invariant the feature depends on (pairing, name-match, ordering, two code paths that must agree), identify the 2+ sites that must agree and **how each derives its value**.

- sites derive from different sources, or at different resolution depth → `Medium`+, `fragile-invariant`, claim = "A uses `<x>`, B uses `<y>`; they agree only for the tested case", fix = "derive both from one source or one function"
- sites agree by construction (same source, same function) → no finding, put it in `cleared`
- then: does any test reference the new functions or this invariant? No test on a load-bearing invariant → `Medium`, `missing-test`. Do not raise this for an invariant L8 proved correct by execution; say so in `cleared` instead.

### L4: Silent failure & robustness

For new error-handling, concurrency, or external-call code:

- fail-fast where best-effort is expected (`asyncio.gather` with default `return_exceptions=False` on an optional step whose failure aborts the run) → `High`, `robustness`
- silent failure, catch → pass → `Medium`, `robustness`. **Exception**: in wbl-eval benchmark runners, catch → break → `score=False` on an API error is intended. Do not flag it.
- unbounded concurrency, or a missing timeout → `Medium`, `robustness`

Beyond catch → pass, these shapes:

- warn-and-continue on a value that changes the measurement. A log line is not a guard → `Medium`, `silent-failure`
- an existence gate that passes on a partial artifact ("if dir exists and is non-empty: return"). Check whether the **writer** is atomic. Atomic writer = clean; direct write = `Medium`
- a fallback that downgrades to a permissive default when input is missing (`None → True`, `"" → "not-needed"`, missing timestamp → "always in window"). Trace what the missing input actually is in production. If it is missing **always**, the guard never engages → `Medium`, `silent-failure`
- an all-failed run that still produces a publishable number → only a finding if the repo lacks a gate for it. Check `conventions` in the BRIEF before inventing one.

### L5: Repo-contract conformance

You are given the repo's own rules in `BRIEF.conventions`, quoted, with their numbers. Walk the diff against them item by item.

- Flag only a violation you can pin to an exact rule and an exact line. Quote both. No style preferences, no "spirit of the doc" inferences.
- Name the rule id in `claim` so the comment can cite it. A cited rule turns a matter of taste into a matter of policy, and the author can act on it without debate.
- If the diff **follows** a rule someone might think it breaks, put that in `cleared`. It stops a later phase from re-raising it.

### L6: Vendored fidelity & external deps

Fetch and probe. Do not trust the PR body.

Vendored trees, for each pin in `BRIEF.vendor_pins`:

```
curl -sL https://github.com/<org>/<repo>/archive/<pin>.tar.gz | tar xz -C /tmp/up --strip-components=1
diff -r --brief /tmp/up <WT>/<vendored dir>
```

- any file differs → `Medium`, `vendor-drift`. Record exactly which files and how. Check every doc that asserts byte-identity. The one thing only the author knows is *why* the upstream edit was needed, so that part is a question, not a claim.
- differs only by "Only in upstream" for assets, docs, or large archives → clean, but note anything the runtime needs that is **not** vendored.

External dependencies the change introduces, as cheap HTTP probes:

- HF dataset/model: `curl -s -o /dev/null -w "%{http_code}" https://huggingface.co/api/datasets/<repo>`. 200 = public, 401 = private **or** nonexistent; anonymous cannot distinguish them, so say so rather than picking one.
- configs and splits actually matching the code's constants: `https://datasets-server.huggingface.co/splits?dataset=<repo>`, then `/rows?...` to check column names and row shapes against the parsing code.
- container image: registry v2 anonymous token → manifest → config blob, which also reveals the real listen port, CMD, and env.

- the code's constants disagree with the live schema → `High`, `broken-reference`
- the resource is missing or private **and** is the only source at runtime → report it, but mark it `type: "external-dep"` and note who can act. Phase 7 routes it to the summary rather than a comment if the author cannot fix it.
- a needed artifact is gitignored and so absent from a fresh checkout (`*.zip`, weights, seeds) → verify the fallback path exists and fails loudly, then report the same way.

### L7: Churn & sibling deviation

- If `churn_suspected`: grep the **net** diff for keywords of any feature added-then-removed across `BRIEF.commits` (model names, deleted modules, temp flags). A leftover reference surviving into the net diff → `Nit` or `Medium` by impact, `churn-leftover`. A clean net diff goes in `cleared`.
- If the change mirrors an existing pattern (sibling language config, sibling benchmark, parallel module): diff the new block against the sibling. Structural deviation not explained by the change's intent → `Medium` or `Note`, `sibling-deviation`. Only intended fields differing → clean.
- "Is this normal?" is answered with repo data, not taste. Rank the thing against its siblings (file sizes, directory layouts, sibling specs) and quote the distribution.

### L8: Execution proof

Pure logic can be exercised without the cluster, the GPUs, or a paid API. Do that.

- Copy the changed module from `WT` into a scratch dir. Stub only the heavy imports (base classes, resolvers); keep the real helper modules.
- Drive the aggregation, limit, sampling, and resume-filter functions with synthetic inputs, **including the degenerate cases**: empty dir, truncated JSON, stale leftovers, error-only records, a single record, zero records.
- Reproduce third-party library behavior in a throwaway venv (`uv venv` plus the pinned version) rather than reasoning from memory about what a library does.

- a function misbehaves → candidate with the **reproducing input** in `evidence`. That is what makes a comment undeniable.
- everything passes → put each exercised function in `cleared` with its inputs. This is what licenses the review to *not* comment there, and it is a review result in its own right.

## PHASE 3: ADVERSARIAL VERIFY

```
3.1 Pool all candidates. Dedup: same file, same line, same mechanism → keep the one with
    the most concrete failure scenario, and record that both lenses hit it (independent
    corroboration is a severity signal). Same line, DIFFERENT mechanism → keep both.

3.2 Cap: verify every candidate. If more than 24 survive dedup, verify the 24 with the
    most concrete failure scenarios and list the deferred ones by file:line in the report (R8).

3.3 Dispatch ONE verifier per candidate, all in one message. The verifier receives: the
    hard rules, WT, the diff, the candidate's claim / failure / evidence / file:line, and
    the relevant files. It does NOT receive the finder's reasoning, the other candidates,
    or the lens name. Its prompt:

      > Be skeptical. Your job is to REFUTE this claim. Return exactly one VERDICT.
      > CONFIRMED: you can name the inputs or state that trigger it and the wrong output
      >   or crash that results. Quote the line.
      > PLAUSIBLE: the mechanism is real, the trigger is uncertain (timing, env, config).
      >   State what would confirm it.
      > REFUTED: factually wrong (the code does not say that) or guarded elsewhere.
      >   Quote the line that proves it.
      > Prefer to settle this by RUNNING the code over reasoning about it: import the
      >   function with synthetic inputs, curl the endpoint, diff the tarball. Set
      >   method="executed" when you did, "read" when you did not.
      > Do not refute a candidate merely for depending on runtime state when that state is
      >   realistic: a value that is null in production, an error path, a cold cache, a
      >   missing optional field, a partial failure. Those are PLAUSIBLE, not REFUTED.

3.4 Resolve:
      REFUTED with method="executed"  → drop. Record it in the report's cleared list;
                                        an executed refutation is a review result.
      REFUTED with method="read"      → drop, UNLESS the candidate came from L8 with a
                                        reproducing input, in which case execution beats
                                        reading: keep it and say the verifier disagreed.
      CONFIRMED / PLAUSIBLE           → promote to FINDING, carrying the VERDICT.
3.5 Re-rank severity using the verdict. A CONFIRMED Medium with a named trigger outranks
    a PLAUSIBLE High whose trigger nobody can name.
```

## PHASE 4: SWEEP & COVERAGE

```
4.1 COVERAGE TABLE. Build it mechanically from every FINDER_RESULT.files_read:
      changed file × which lenses opened it.
    BRANCH:
      a changed file no lens opened → you have a hole. Either dispatch a targeted finder
          at it now, or declare it in the report (R8). Do not let it pass silently.
      a body_claim from BRIEF that no lens landed on → same treatment.
      a lens returned non-empty `blocked` → that check did not happen. Retry it yourself
          if you can; otherwise it goes in the report as a stated gap.

4.2 SWEEP. Dispatch ONE fresh finder holding the verified FINDING list and the BRIEF, with:
      > You are a fresh reviewer. Here is what has already been found and verified. Do NOT
      > re-derive, re-confirm, or restate any of it. Your only job is what is MISSING.
      > Re-read the diff and the enclosing functions, and focus on what a first pass tends
      > to miss: moved or extracted code that dropped a guard along the way; a config
      > default quietly flipped; setup/teardown asymmetry in tests; a dataclass default
      > evaluated once; a lock scope that shrank; a predicate method with a side effect;
      > the largest changed file, which reviewers skim; and every block the diff DELETED.
      > Return up to 8 candidates that are not already on the list. If there is nothing
      > new, return an empty list. Do not pad.
4.3 Any sweep candidate goes back through Phase 3 verification before it can become a
    FINDING. The sweep is not exempt.
```

## PHASE 5: CI

```
5.1 CHECKS ← gh pr checks PR
5.2 Record each check pass/fail. A failing required check is itself High.
5.3 Read the check LIST, not just the verdicts. "skipping" is not "passing": a path filter
    may have excluded the very tests that cover this change. If a relevant-looking suite was
    skipped, say which one and why (usually a detect-changes path filter).
5.4 Know what a green check does NOT prove:
      - a param/registry lint proves the spec's SHAPE (exhaustive keys, null-vs-value,
        signature match), never that the values are semantically right or that they reach
        the model. That is L2's job.
      - a lint/type job that passes because the new tree was added to an exclude list proves
        only that the exclusion works. Check the exclusion was added in EVERY place the repo
        requires (root and sub-project configs, build-system ignores), and that nothing
        outside the vendor tree got excluded along with it.
      - a large-file/LFS check proves size limits, not that committed data BELONGS in the
        repo. For added data files ask: is it upstream's own tracked content, does any code
        read it, and does it duplicate the runtime source (a dataset on a hub)? Divergent
        duplicate data is a provenance finding, not a size finding.
      - unit tests passing says nothing about a benchmark's numbers. Those live in L8.
```

## PHASE 6: EMIT REVIEW (post nothing)

```
6.1 Print, in this order:
      - One-line verdict: mergeable? what blocks it?
      - What ran: the lens fleet, the verify count (n candidates → n confirmed / n plausible
        / n refuted), and the sweep result. If the Agent tool was unavailable and this was a
        single-context run, say so here.
      - What was verified CLEAN: the pooled `cleared` lines, especially the L6 probes and the
        L8 executions with their inputs, plus executed refutations from 3.4. A cleared area is
        a review result, and it is what justifies not commenting there.
      - Findings table: severity | file:line@HEAD | problem | fix | verdict.
      - Gaps (R8): lenses skipped, candidates deferred past the 3.2 cap, changed files no lens
        opened, body_claims nobody landed on, blocked probes.
      - CI status + mergeable/mergeStateStatus.
6.2 Lead with High/Medium. Separate Note/Nit.
6.3 Proceed to PHASE 7 and draft comments. Do not ask first.
```

## PHASE 7: DRAFT COMMENTS (always, after Phase 6)

```
7.0 COMMENT GATE. Report precision is one bar; comment precision is a higher one.
    Comment only a finding whose verdict is:
      CONFIRMED                          → comment
      PLAUSIBLE with method="executed"   → comment
      PLAUSIBLE with method="read"       → comment ONLY if the mechanism is proven and the
                                           uncertainty is purely about the trigger. Otherwise
                                           it stays in the report and out of the author's inbox.
    Then drop a finding from the comment set when:
      - L8 proved the code correct and the only residue was your own doubt
      - the author cannot act on it (an artifact only the reviewer's org can publish,
        infrastructure access) → it becomes an ops note in the summary, addressed to the user
      - it merely restates a convention the code already follows (check L5's `cleared` first)
    Keep it when the fix is in the author's hands, even if it is a Nit.
    Order the emitted comments by severity so the user can cut the tail.

7.1 For each finding to comment, re-read the anchor at WT and confirm line still points at
    the intended code. Line numbers from the fleet are HEAD line numbers by construction
    (R1), so this is a cheap confirmation rather than a re-derivation. If the PR was updated
    mid-review, HEAD moved: rerun Phase 0.7 and re-anchor.

7.2 Compose body in STYLE = ko-formal, SHORT & SIMPLE:
      - 1-2 sentences. No preamble, no restating the code, no hedging.
      - State the problem; add the fix only if it is not obvious from the problem.
      - Korean with 입니다/습니다 endings.
      - English (Latin) for all technical/computing terms (timeout, env, default, override,
        regex, semaphore, ...). Hangul only for native grammar and words.
      - No Korean gloss in parens after an English term.
      - Reference cross-file evidence as `path:line`.
      - When the finding cites a repo rule (L5), name the rule: "GUIDELINE item 7".

7.3 Emit each as: file · Line N · body. One block per comment.
7.4 The user posts them. Do NOT call gh to post.
7.5 Clean up: git worktree remove --force "$WT". Do this only after the user has what they
    need; if they are likely to ask a follow-up (N5), keep WT and say it is still there.
```

---

## Repo hooks (repo-specific contracts this skill knows about)

### wbl-eval (`eval/wbl-eval/**` in the solar-system monorepo)

If any changed path is under `eval/wbl-eval`, `eval/wbl-eval/docs/GUIDELINE.md` is the review contract. Read it in Phase 0.6, carry the touched sections into `BRIEF.conventions`, and cite them by item or rule number. L5 runs on it.

Map findings onto the guideline instead of arguing them from first principles:

| what you found | lens | cite |
|---|---|---|
| a generation param the wrapper hand-picks or drops on the way to the model | L2 | item 7 (forward the full `parameters`, never a few CLI flags), P10 |
| an unset profile value replaced by a wrapper or vendored default | L2 | P4 decision tree (case 3 "omit" is allowed only when the downstream default was actually read at its source) and P4's "never duplicate a downstream default into the wrapper", item 5 |
| `null` reaching a request body, env file, or generated config | L2 | P2 null contract, P10, rule 21 |
| `params.get(k, DEFAULT)` or `if "k" in params` on raw registry dicts | L2 | P2 (null swallows the default) |
| a ctor default that is not `None` while the code branches on `is None` | L2 | P2's terminal_bench detector (default ≠ None ∧ `is None` branch ∧ spec null ⇒ bug) |
| a declared spec arg nothing consumes, or consumption proven only at the first hop | L1 | P7 and item 19 (grep the receiving side for the exact name) |
| a vendored tree that differs from its upstream pin | L6 | P5 and item 21 |
| a benchmark arg named like a generation param (`seed`, `timeout`, `temperature`) | L5 | P3's `benchmark_` prefix family, rule 7 |
| a timeout arg without a `_sec`/`_min`/`_ms` suffix | L5 | item 12, rule 20 |
| an inlined seed literal instead of `DEFAULT_SAMPLE_SEED` | L5 | P3, rule 8 |
| dataset not loaded through dloaders, or not mirrored to the private Upstage HF space | L6 | items 8 and 9 (a 401 on the mirror is the *expected* private state; the real question is whether the run env has the token) |
| missing `total_samples` / `success_samples` in result info | L5 | item 10, rule 23 |
| a progress denominator that grows during the run | L4 | item 14 (true total from the first line) |
| base-contract drift (`limit`/`max_concurrency`/`log_path` not propagated, `os.environ` copy, per-call log kwargs, provider if/elif instead of the shared resolver) | L1, L3 | P9 and items 13a-13g |
| a benchmark-side `if not records: return {...0...}` | L4, L8 | P9, item 13f |

CI semantics for this repo (Phase 5):

- `wbl-eval-param-lint` runs `make param-check`. Green proves spec SHAPE (exhaustiveness, no generation params in `args:`, name collisions, base signatures, grouping/order, timeout suffixes). It proves nothing about whether a value reaches the model, which is exactly why L2 exists.
- Part C's own warning applies to you too: success is the literal line `param-standardize: 위반 없음 ✅`, not merely exit 0.
- The lint's scan skips vendored trees and dot-directories by design, so a finding inside `{bench}/src/**` will never be lint-caught. That is L6's job.
- A new vendored tree must be excluded in four places (both `[tool.ruff]` and `[tool.mypy]` excludes in `eval/wbl-eval/pyproject.toml`, the monorepo root `pyproject.toml` ruff exclude, and root `pants.toml` `pants_ignore`). The root one is the commonly missed one, because a bench-local `make lint` still passes without it.

---

## Notes for the operator (you)

- N1. If the primary working tree shows different content than `WT`, trust `WT` (R1) and say so.
- N2. The user lands out-of-band fixes on related PRs without mentioning them. If a premise looks already-fixed, re-check git and PR state before reporting it as broken.
- N3. Distinguish "looks like a bug" from "dead / overwritten / intended". That distinction is what Phase 3 is for; do not pre-empt it inside a finder by suppressing the candidate.
- N4. Two findings per review are worth more than twenty. The scarce resource is the author's attention. The fan-out exists to raise recall at the *finding* stage; the 7.0 gate is what keeps the comment set small. Never let a wide fleet turn into a wide comment list.
- N5. When the user asks a follow-up ("does anything override X?", "is Y normal?"), treat it as a missing lens, not a one-off answer: dispatch the trace against `WT`, then fold the result back into the finding set and the comment list.
- N6. Independent corroboration is real signal. When two blind lenses land on the same line for different reasons, that finding is stronger than either finder knew, and it deserves the severity bump 3.1 records.
- N7. A finder that returns nothing is a result, not a failure. Its `cleared` list is what lets Phase 6 say an area was checked. Push back on empty `cleared` and empty `blocked` together: that means the lens did not actually run.
