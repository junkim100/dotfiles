---
name: test-audit
description: Apply lightweight test-quality checks when writing, modifying, or reviewing tests, including regression tests during bug fixes. Audit an existing suite when asked to assess its quality or coverage. Keep ordinary work scoped to the tests involved in the task.
license: MIT
---

# Test Audit

Improve the confidence tests provide relative to their maintenance cost. Apply a short quality check during normal development; use the audit guidance only when the requested task includes evaluating an existing suite. This skill does not require adding tests to every change.

## During normal work

Read the relevant repository instructions, nearby tests, and the behavior being exercised. Use the project's test framework and conventions. Before adding or changing a test, identify:

- The behavior or contract it protects and a plausible mistake that should make it fail.
- What the test contributes beyond nearby coverage. Extending an existing case may be sufficient; separate unit and integration tests are useful when they catch different failures.
- Whether the assertions observe the real behavior or merely confirm setup, mock return values, or the implementation's current shape.

Prefer the narrowest stable boundary that exposes the failure. A public function, command, service boundary, or externally observable side effect may be appropriate; a full end-to-end test is not always necessary. Mocks and dependency injection are useful for isolating external services, time, randomness, or failures. Check that the component under test still performs the work being asserted. Avoid widening production APIs solely for convenient assertions when an existing boundary is sufficient.

For a bug fix, aim to demonstrate that the regression test fails for the reported bug before the fix and passes afterward. Check the failure reason: missing dependencies, an unrelated guard, or broken test setup do not establish the regression. Use an isolated reproduction when necessary to preserve current work. If a before-fix run is unsafe or impractical, state what was verified and the remaining uncertainty; do not claim the test proved more than it did.

Keep this reasoning brief and usually internal. A small change should not produce a separate audit report or trigger cleanup outside the task.

## Look for false confidence

- Expected results computed by the same code being tested can reproduce its mistake. Use an independently justified result or invariant.
- A mock that supplies the behavior under examination can make broken production code look correct. Exercise the component responsible for that behavior.
- Error tests can pass for the wrong reason. Supply otherwise valid input and check the intended failure; include a valid control when it distinguishes a meaningful risk.
- Assertions about private call sequences, source spelling, or large snapshots can make harmless refactors expensive. Prefer behavior assertions unless the exact order, text, structure, or bytes are themselves a contract.
- Repeated coverage can cost more than it adds. Retain separate cases when their inputs, integration boundaries, or failure modes differ materially.

Treat these as evidence to investigate, not automatic rejection rules. A smoke test can detect startup failures without an explicit assertion. Static checks, snapshots, configuration checks, security regressions, and compatibility tests can protect real contracts. For example, an installer test should exercise a temporary home directory or a dry run to check its promised effects; inspecting its source may still be appropriate for a rule about prohibited commands.

## When auditing existing tests

Start with the requested files or subsystem. For each actionable finding, inspect the test, the implementation it exercises, nearby coverage, and relevant history when the original purpose is unclear. Explain the concrete failure it misses or maintenance burden it creates, with file locations and evidence.

Review requests produce findings and recommendations. Make cleanup edits when the user's task authorizes them. Before removing coverage, identify the contract it protects and show where that protection remains, or explain why the behavior is obsolete. Keep uncertain cases and describe the uncertainty. A slow test, a test-only dependency, or a failing baseline is not sufficient evidence for deletion. Avoid optimizing for fewer tests or fewer lines of code.

## Validation and reporting

Run the focused tests relevant to the change and any checks required by the repository. Broaden validation when shared behavior, integrations, or failures justify it. Discover commands from the repository's scripts, manifests, and CI configuration; do not assume a language or runner. Use temporary fixtures or supported dry runs for installers and other tests that could alter a live environment.

Report meaningful coverage changes, checks actually run, and material gaps. Distinguish new failures from baseline failures. For a review, focus on actionable risks; for a small implementation change, a short validation note is enough.

Adapted from [OpenClaw's test-audit skill](https://github.com/openclaw/openclaw/blob/d43208fc55c789f0b03e1a632ccfddb7b1d0a798/.agents/skills/test-audit/SKILL.md). This version replaces its repository-specific workflow with guidance for routine development across projects. The upstream license is retained in [LICENSE](LICENSE).
