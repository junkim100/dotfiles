---
name: doubt-driven-development
description: Check consequential assumptions during planning, implementation, debugging, and review. Use when an unverified assumption could invalidate results, cause data loss, waste an expensive run, or require substantial rework. Keep checks scoped to the current task.
---

# Doubt-Driven Development

Find evidence against important assumptions before relying on them. Focus on concrete ways the current approach could fail.

## When to apply

Apply when correctness depends on an unverified assumption with meaningful consequences, especially:

- Results depend on scoring, filtering, aggregation, or sample identity.
- Cached or partial results are being reused under potentially changed conditions.
- Configuration or data crosses boundaries where it could be dropped, defaulted, or transformed.
- Behavior depends on an interpreter, filesystem, dependency version, or execution environment.
- An expensive run or consequential operation depends on an untested setup.
- A design choice depends on an uncertain property such as ordering, idempotence, or concurrency.

Use ordinary verification for mechanical edits and straightforward changes whose relevant behavior is already established. Change size alone does not determine whether this skill applies.

## Check the assumption

1. Identify the few assumptions most likely to change the outcome, usually one to three. State each as a checkable claim and identify the consequence if it is false. Establish expected behavior from the task, specification, or relevant code; keep inference separate from established requirements.
2. Choose the smallest practical check that could contradict the claim. Prefer a focused reproduction, a discriminating fixture, or tracing the value through its actual consumers. Reuse existing evidence when it covers the same claim and conditions.
3. Preserve the conditions that matter. Check the relevant execution path, environment, and input shape. A mock that supplies the disputed behavior, or a probe in a different environment, does not establish that the real behavior works.
4. Evaluate the evidence. Confirm that a failure concerns the assumption rather than broken setup or an unrelated error. Treat a plausible objection as a hypothesis until supported. A passing check supports only the conditions exercised.
5. Correct supported defects within the authorized task and verify the affected behavior. If evidence is inconclusive, state what remains unknown and how that limits the conclusion. Accept that a check may find no actionable issue.

## Keep the work proportional

Start with one focused pass. Extend it when new evidence, a changed implementation, or unresolved consequences justify further investigation. Avoid repeating checks on unchanged behavior without a concrete reason.

Use disposable fixtures or supported dry runs for checks that could alter data. This skill does not authorize additional deployments, costly jobs, or changes outside the user's task.

A useful check does not always require a new test. When tests are involved, follow the available test-audit guidance. Verification already performed during a review can satisfy this skill; do not repeat it merely to complete another workflow.

Ask the user only when resolving a material uncertainty requires their intent, unavailable information, or additional authorization. Continue independent work where possible.

## Reporting

Keep routine reasoning brief. Include the significant assumption checked, the evidence obtained, and any material limitation in the normal task update or final validation note. A separate report is unnecessary unless requested.

Distinguish inspection, executed checks, and independent review. Never describe self-checking as independent review.

Inspired by [Addy Osmani's doubt-driven-development skill](https://github.com/addyosmani/agent-skills/blob/main/skills/doubt-driven-development/SKILL.md). This adaptation focuses on direct verification during ordinary work.
