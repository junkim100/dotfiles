# House rules

Standing rules from the user's review feedback. Apply each rule only inside its scope (SKILL.md R11).

Add a rule here only when the user states a preference that applies beyond one PR. A decision about one PR (accepting an exception, asking for blocking-only or medium-only comments, calling a validation gap not severe) is local: it goes in that review's ledger record, never here. Every rule names its scope, the phase it governs (discovery, selection, writing), its source, and its limit, so it cannot quietly grow into a broader filter than the user asked for.

Sources point at the 2026-10-21 review study kept locally under `~/.local/state/pr-review/study-2026-10-21/` (W2 draft and follow-up ledgers) or at later ledger records.

## Global

### G1. A visibly failing CI check needs no comment
- Scope: any repository. Phase: selection (`held_reason: ci-visible`).
- Rule: hold a finding whose only consequence is a check that is already visibly failing on the PR for the same cause. The author sees it and fixes it without being told.
- Limit: a validator or test that CI does not run, a failure that appears only after merging with the base, or a check that passes for the wrong reason is not visible; comment it.
- Source: user feedback 2026-08 (W2 follow-up H1241); counterexample of a posted local-validator finding in W2 (S17).

### G2. State the guideline rule in words, not its number
- Scope: repositories with a review guideline. Phase: writing.
- Rule: when a finding violates the guideline, the comment says what the guideline requires and what the code does instead, in words: `GUIDELINE.md에서는 profile의 parameters를 전부 실제 request까지 전달하도록 되어 있는데, 여기서는 ...`. When the applicable document is `GUIDELINE.md`, name that file instead of calling it `내부 가이드라인`. Never write item numbers (`item 7`, `P9`, `25c`) in a comment; they stay in the report and the checklist table, which are for the user. Do not invoke the guideline for a finding no rule covers, and never cite internal knowledge bases (a wiki, meeting notes) in a comment; cite code, pinned upstream permalinks, or the PR itself.
- Limit: when the user settles a point outside the guideline for one PR (a team decision, an accepted exception) or asks for a comment without guideline references, follow that for that PR.
- Source: user feedback 2026-10-25 ("I don't want the reviews to mention specific guideline numbers ... just mention according to the guideline"). This replaces the 2026-10-22 version that put item numbers in comments; the guideline-first review itself (2026-10-22, "the most important thing is following the repo guideline properly") is unchanged.
- Source: user feedback 2026-10-26 on PR #1694: comments should say `GUIDELINE.md`, not `내부 가이드라인`. The decisions to omit the CI and general PR comments remain specific to that review.

### G3. Tone and words
- Scope: Korean comments. Phase: writing.
- Rule: recommendations end softly, `~해야 할 것 같습니다`, `~할 수도 있을 것 같습니다`; questions use `~어떨까요?` or `~이유가 있었을까요?`. Prefer everyday verbs to jargon verbs (`바꿔야 할 것 같습니다` over `bind 해야 합니다`). English for technical terms, no Korean gloss after them. No praise, no preamble, and no sentence restating what is already correct.
- Limit: the softer ending softens the recommendation, not the confidence in verified evidence.
- Source: user feedback 2026-09 (W2 follow-ups S12-T32, S27-T14, H749, H906).

### G4. A removal request is one sentence
- Scope: any repository. Phase: writing.
- Rule: asking to delete a stray file or block is one sentence (`이 파일은 삭제해야 할 것 같습니다.`). The reasoning goes to the user in the report, not to the author, unless the author could not see why.
- Source: user feedback 2026-09 (W2 follow-up S31-T11).

### G5. A value that differs from its source: fact, permalink, reason, conditional fix
- Scope: any repository. Phase: writing.
- Rule: when a value differs from upstream or another pinned source and the difference could be deliberate, state the verified fact with a pinned permalink, ask whether there was a reason, and make the fix conditional (`특별한 이유가 없다면 ~로 맞추고 test 값도 같이 바꿔야 할 것 같습니다`).
- Limit: when the difference is clearly accidental or provably breaks the evaluation, state it as a defect instead of asking.
- Source: user feedback 2026-09 (W2 follow-ups S31-T8, S31-T10).

### G6. Inline over general comments
- Scope: any repository. Phase: writing.
- Rule: anchor a comment to a line whenever one exists. Use a general PR comment only when no line fits or the user asks for one.
- Source: user feedback 2026-08 (W2 follow-ups H757, H758).

### G6a. One request per comment, and no review body
- Scope: any repository. Phase: writing and posting.
- Rule: every request is its own comment. Never put requests into a review body, and never combine several requests into one comment, a general one included. GitHub takes line comments only on lines of the PR diff, so a draft whose fix line is outside the diff is posted as a file comment on that file when the PR changes it, otherwise as its own general PR comment; either way its text names the `path:line`.
- Source: user feedback 2026-10-30 on PR #1706, where three requests were posted together in one review body.

### G7. Reminders for unresolved items
- Scope: follow-up reviews. Phase: writing.
- Rule: unresolved items from earlier rounds go in one short comment without bullets, naming each `file:line`. Resolved items are not repeated.
- Source: user feedback 2026-08 (W2 follow-ups H933, H936).

### G8. Upstream-faithful behavior is not a defect
- Scope: ports, migrations, and wrappers of upstream code. Phase: discovery and selection.
- Rule: if the PR does what the upstream implementation does, it is fine. Point out only what keeps the evaluation from completing or measuring as upstream designed: a dropped parameter, a missing step, a changed denominator, a different execution environment.
- Limit: the repository's own contract can still require a deviation from upstream (a documented override, an error-handling policy); that is a contract finding, not an upstream-parity one.
- Limit (order): G8 applies only after showing the behavior matches upstream. Before proposing stricter preflight, retries, or failure handling around a vendored harness, compare its native failure behavior; if the change would disable an upstream fallback, name the repository rule or authorized policy that requires it, otherwise keep it a question.
- Source: user feedback 2026-09 (W2 follow-up H1636).

## wbl-eval (`eval/wbl-eval/**` in the solar-system monorepo)

### W1. Linux hosts only
- Phase: discovery and selection.
- Rule: wbl-eval runs only on Linux servers. Never raise macOS or platform-portability findings; a test that fails only on macOS is not a finding.
- Source: user feedback 2026-09 (W2 S34-T3).

### W2. Cost limits
- Phase: selection.
- Rule: `per_instance_cost_limit: 0`, or official cost limits relaxed at runtime for self-hosted models, is accepted. `call_limit` changes stay reviewable.
- Source: user feedback 2026-07 and 2026-08 (W2 follow-up H436).

### W3. Deliberate presets are not copied defaults
- Phase: discovery.
- Rule: an explicit spec value that differs from the constructor default is a deliberate preset, even for a provider or mode that is not selected right now. The exhaustive-null rule (GUIDELINE P2) targets copied defaults, not intended presets; do not ask to null them.
- Limit: W3 covers values, not file shape: a deliberate preset does not excuse a profile's line-shape rule (GUIDELINE item 24). W3 only rules out asking to null an intentional preset. It does not answer why the preset differs from a pinned upstream value; that stays a G5 question when no decision is linked.
- Source: user feedback 2026-09 (W2 S10-T13, S10-T14).

### W4. Benchmark PRs do not change shared policy on the side
- Phase: discovery (scope boundary).
- Rule: a benchmark migration or fix that also edits shared policy (GUIDELINE, registry READMEs, common sections of migration docs, official-promotion rules) gets a request to remove those edits and propose them in a separate PR, unless the PR's stated purpose is that policy. Keep any change CI needs, including a narrow CI selection change that makes the tests this PR adds run. A PR that generalizes its own one-off exception into global policy is the common case.
- Source: user feedback 2026-09 and 2026-10 (W2 S13-T6 and the posted comments that followed; S24-T27).
