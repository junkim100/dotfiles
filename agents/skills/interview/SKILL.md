---
name: interview
description: >
  Use when the user types /interview, or asks Claude to interview them, ask clarifying questions, or pin down requirements before doing a task.
  Turns a task request into a short multiple-choice interview (AskUserQuestion) that settles goal, scope, behavior, constraints, and verification, always ends with an open "anything else?" question, then prints a requirements brief and carries out the task against it.
  Asks only what the codebase cannot answer; everything in code is Claude's to check.
---

# /interview: requirements interview before doing a task

Runs Phases 0-4 in order. Pseudocode is normative. Take each rule literally.

Topology: **ground in the repo, then draft questions, then ask in rounds, then the open question, then brief and build**.

The interview exists because intent lives only in the user's head. Everything else lives in the code, and reading it is faster and more accurate than asking. A good interview is short, each question is a real fork in the design, and the brief at the end is something the user can correct line by line.

## Invocation

- `/interview <task>`: the argument is the task.
- `/interview` alone: the task is the most recent request in the conversation. If there is none, ask for it in one plain sentence, without AskUserQuestion.
- Also applies when the user says "interview me", "ask me questions first", or "make sure you understand what I want before starting".
- `--deep` raises the caps in R4. `--brief-only` stops after Phase 4's brief without doing the task.

## Hard rules

- R1. Every question must change what you build. Before keeping a question, name the two different implementations its answers lead to. If you cannot, drop it.
- R2. Never ask what the repo, git history, tests, or docs can answer. Read first. Ask only when the reading is genuinely ambiguous, and then say what you found so the user is choosing between real states, not guessing at them.
- R3. Options are concrete, mutually exclusive alternatives, each with a one-line consequence in its description. Put your recommended option first, label it "(Recommended)", and say why in its description. Never offer an option you would refuse to build.
- R4. Bound the interview: at most 3 rounds and 10 questions by default, 5 rounds and 20 with `--deep`. Stop earlier when no remaining question passes R1.
- R5. Batch independent questions into one AskUserQuestion call, up to 4. Ask dependent follow-ups in the next round, never in the same one.
- R6. Always end with the open question in Phase 3, even when everything seems settled. It is the only question that can surface what you did not think to ask.
- R7. Record every answer in the brief: chosen options, free text typed under "Other", and the defaults the user accepted by picking the recommended option. Also record the assumptions you did not ask about, with their evidence.
- R8. Do not start the task before the brief is printed. After the brief, do the task, unless plan mode is active (the brief becomes the top of the plan), `--brief-only` was passed, or the user says stop.
- R9. Never pad a round. If Phase 0 leaves one real question, ask one question.
- R10. Leading questions are forbidden. Do not phrase options so that one is the only reasonable pick; if that is the case, it is a default, not a question (R1).

## Phase 0: Ground

- 0.1 Restate the task privately in one sentence. List the nouns it touches: components, files, commands, users, data.
- 0.2 Reconnoiter the repo: the files those nouns map to, the patterns they already follow, the tests that cover them, the conventions in `CLAUDE.md` and `AGENTS.md`, and the last few commits that touched the same area. Use an Explore subagent when the area is broad. Time-box this: it is reconnaissance for question-writing, not implementation.
- 0.3 Write down privately what you would assume if you had to start now. Each assumption you are confident in becomes a stated default in the brief. Each assumption you are not confident in becomes a candidate question.
- 0.4 Write down the ambiguities in the request itself: words with more than one reading, an unstated success criterion, a scope boundary the user did not draw.

## Phase 1: Draft the question set

Pick candidates only from what Phase 0 left uncertain. Coverage checklist, in the order that usually changes the work most:

- Outcome: what "done" looks like and who consumes the result.
- Scope: what is in, what is out, adjacent things not to touch.
- Behavior: interfaces, inputs and outputs, error handling, edge cases.
- Constraints: compatibility, performance, dependencies, platform, style.
- Tradeoffs: where two valid designs exist (simple versus general, fast versus safe, minimal versus complete).
- Verification: how the user will judge it, which tests are expected, what manual check they will run.
- Delivery: branch, commit, PR, docs, where the result should live.

Run every candidate through R1 and R2. Sort survivors by how much they change the work. The biggest forks go in round 1.

## Phase 2: Ask in rounds

For each round, one AskUserQuestion call with 1-4 questions:

- `header`: at most 12 characters, naming the topic (for example "Scope", "Errors", "Tests").
- `question`: one complete sentence ending in a question mark, with the context the user needs to answer it. Quote what you found in the repo when the answer depends on it.
- `options`: 2-4, recommended first with "(Recommended)", each description stating the consequence ("adds a migration; existing rows get NULL").
- `multiSelect: true` when choices are not exclusive (which tests to write, which platforms to support).
- `preview` when the options are shapes the user should compare: an API signature, a CLI transcript, a file layout, a config snippet.

After each round, re-plan before the next one. Answers make some drafted questions moot (drop them) and open new forks (add them, subject to R1 and R4). When an answer contradicts something Phase 0 found in the repo, say what you found and ask which wins, in the next round.

Stop when no remaining question passes R1, or the R4 cap is hit.

## Phase 3: The open question

Always the final AskUserQuestion of the interview:

- `header`: "Anything else"
- `question`: "Anything else I should know before I start? Constraints, preferences, worries, or context I did not ask about."
- `options`: "Nothing else, go ahead" (first) and "There is more (pick Other and type it)".

If the typed answer opens a new fork that passes R1, one extra round is permitted beyond the R4 cap. Then ask the open question again, once.

## Phase 4: Brief and proceed

Print the brief in this shape, then act on it:

```
## Interview brief
Task: <one sentence>

Decisions
- <topic>: <chosen option>. <consequence in one sentence>
- <topic>: <chosen option> (recommended default, accepted)

Defaults taken without asking
- <assumption> (evidence: <path:line or command>)

Out of scope
- <thing not to touch>

Done when
- <the verification the user named, or the one you will run>
```

Then do the task against the brief. If a later discovery contradicts a decision in the brief, stop and ask that one question; never silently revert a decision. If the user corrects a line of the brief, update the brief and continue from there.

## Question craft

| bad | why | good |
|---|---|---|
| "How should errors be handled?" | abstract, no fork | "When the upstream API times out, should the CLI: retry three times then fail (Recommended) / fail immediately / return the cached result?" |
| "Do you want tests?" | the answer is always yes | "Which tests? Unit only / unit plus an integration test against a live server / none, you will test manually" |
| "Which test framework should I use?" | the repo already says | (checked: pytest via `pyproject.toml`; stated as a default in the brief) |
| an option list where one is obviously correct | not a real fork | drop it, state it as a default |
| four questions about naming | none changes the work | at most one, or none |

The line between /interview and reading: intent, priorities, and taste are the user's. Facts about the code, the registry, the environment, and the tests are yours to check. Never hand a check back to the user as a question.

## Notes for the operator (you)

- N1. "You decide" means pick the recommended option and record it in the brief as a delegated decision.
- N2. "Just do it" mid-interview means stop asking, print the brief with the remaining items as defaults, and proceed.
- N3. A user who answers with a long free-text paragraph has often answered the next two questions as well. Re-read it before the next round and drop what it covers.
- N4. When no interactive answer channel exists (a non-interactive run), do not interview. State the assumptions you would have asked about and proceed.
- N5. Keep the interview to the task at hand. Broader preferences the user reveals are worth saving to memory, not worth another round.
