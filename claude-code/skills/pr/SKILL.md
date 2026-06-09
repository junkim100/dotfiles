---
name: pr
description: >
  Use when the user types /pr <N> or asks to review a GitHub pull request.
  Verification-first PR review: fetches the PR at its head SHA, checks every
  claim, reference, and feature-invariant against actually-pushed code (never
  the working tree, never the author's reply), classifies findings by severity
  with exact file:line anchors at head, prints a review, and ON REQUEST drafts
  post-ready inline comments in the user's Korean style. Does not post anything;
  the user posts comments himself.
---

# /pr — verification-first PR review

Reviews PR `<N>` (Phases 0–6), then drafts comments only when the user asks (Phase 7).
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

## Schemas (handoff between phases)
```
FINDING = {
  id:        int,
  severity:  "High" | "Medium" | "Note" | "Nit",
  type:      "broken-reference" | "dead-code" | "contract-mismatch"
           | "fragile-invariant" | "churn-leftover" | "sibling-deviation"
           | "robustness" | "missing-test" | "other",
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
```

## PHASE 1 — GROUND TRUTH HELPERS
```
1.1 Define (do NOT read working-tree copies of these files):
      fileAtHead(F) :=
        gh api repos/:owner/:repo/contents/F?ref=HEAD -q .content | base64 -d
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
```

## PHASE 6 — EMIT REVIEW (post nothing)
```
6.1 Print, in this order:
      - One-line verdict (mergeable? what blocks?).
      - What was verified (the checks you actually ran, so the user trusts the result).
      - Findings table: severity | file:line@HEAD | problem | fix.
      - CI status + mergeable/mergeStateStatus.
6.2 Lead with High/Medium. Separate Note/Nit.
6.3 Offer: "Want me to draft these as PR comments?" → if yes, PHASE 7.
```

## PHASE 7 — DRAFT COMMENTS (only when the user requests)
```
7.1 For each FINDING to comment:
      re-run fileAtHead(file) and confirm line_at_head still points at the
      intended code (anchor may have moved if the PR was updated). Update line.
7.2 Compose body in STYLE = ko-formal:
      - Korean with 입니다/습니다 endings.
      - English (Latin) for all technical/computing terms (timeout, env, default,
        override, regex, semaphore, ...). Hangul only for native grammar/words.
      - No Korean gloss in parens after an English term.
      - Lead with the problem in one sentence; add the fix only if it adds signal.
      - Reference cross-file evidence as `path:line`.
7.3 Emit each as: file · Line N · body.  (one block per comment)
7.4 The user posts them. Do NOT call gh to post.
7.5 Offer a shorter variant of any comment on request.
```

## Notes for the operator (you)
- N1. If the working tree shows different content than fileAtHead, trust fileAtHead (R1) and say so.
- N2. The user lands out-of-band fixes on related PRs without mentioning them; if a premise looks already-fixed, re-check git/PR state before reporting it as broken.
- N3. Distinguish "looks like a bug" from "dead / overwritten / intended." Trace before flagging.
