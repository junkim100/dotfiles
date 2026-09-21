---
name: quiz
description: >
  Use when the user types /quiz, asks to be quizzed or tested, or wants to check their understanding of code: something Claude just implemented, a merged or open PR, a PR branch, a file or directory, or a whole repository.
  Studies the scope, builds a hidden answer key of the concepts needed to extend or debug the code, asks adaptive multiple-choice and short-answer questions via AskUserQuestion, grades each round with file:line evidence, retests misses from a new angle, then reports the score, the gaps, and what to read.
  Understanding is the bottleneck; the quiz is the speed regulator. Read-only.
---

# /quiz: test the user's understanding of code

Runs Phases 0-4 in order. Pseudocode is normative. Take each rule literally.

Topology: **resolve scope, then study and build the answer key, then ask in rounds, grading after each, then report gaps with reading pointers**.

The point is the one Geoffrey Litt makes in "Understanding is the new bottleneck": agents can verify code, but a person can only steer and iterate on what they hold in their head. The quiz checks whether the concepts are there, so the user can decide whether to keep going, re-read, or ask for an explanation. Trivia proves nothing; a passed quiz should mean the user could extend or debug this code tomorrow.

## Invocation and scope

| form | scope |
|---|---|
| `/quiz` | if this session changed files: those changes and the decisions behind them; else if the current branch differs from the default branch: the branch diff; else the repository |
| `/quiz this` or `/quiz impl` | what Claude implemented in this session |
| `/quiz pr <N>` or `/quiz #N` | pull request N, merged or open, plus the code it touches |
| `/quiz branch [name]` | the named branch (default: current) against its merge-base with the default branch |
| `/quiz repo` | the whole repository, at the architecture level |
| `/quiz <path>` | that file or directory |
| `... --n <N>` | question count (defaults: 6 for a small diff, 8 for a PR or branch, 10 for a repository) |
| `... --topic "<t>"` | concentrate the questions on one theme inside the scope |
| `... --hard` | start at difficulty 2 and include more change-impact and failure questions |

When an argument could be a path or a topic, check for the path first. If the user asks in prose ("quiz me on the auth flow"), map it onto this table.

## Hard rules

- R1. Build the answer key before asking anything. Every correct answer is verified by reading the code in scope, never taken from memory, the PR description, or a commit message. Each key entry carries a `path:line` that settles it.
- R2. Never reveal the key, the upcoming questions, or the correct option before the user answers. Grade after each round, not before.
- R3. No trivia. Names, line counts, and paths are never the point of a question. Ask what someone needs in their head to extend, debug, or review the code: structure, flow, decisions, contracts, failure modes, change impact.
- R4. Distractors are real misconceptions. Each wrong option is something a skimmer would plausibly believe, and something the code falsifies. No joke options, no obviously wrong options, no option that is true here but phrased to look false.
- R5. Every multiple-choice question includes a "Not sure" option so guessing is not rewarded. Grade "Not sure" as a gap, distinct from a miss.
- R6. Grade honestly. Right is right, wrong is wrong. "Partially right" exists only for short-answer questions, and the feedback names the missing part.
- R7. Adapt. After a miss or a "Not sure", retest the same concept later from a different angle. After a hit, go deeper in that area or move on.
- R8. Feedback carries evidence. For every question, after grading, give the `path:line` that settles it and, for a miss, one sentence on why the chosen option is tempting.
- R9. Read-only. The quiz never edits files, commits, pushes, or posts. PR data comes from `gh` read commands only.
- R10. No sycophancy in the report. A 4 out of 10 is reported as 4 out of 10, with what to read. Encouragement is fine; inflation is not.

## Phase 0: Resolve scope

- 0.1 Parse the argument against the table above. Record `SCOPE = {kind, ref, paths, n, topic, hard}`.
- 0.2 Materialize the scope:
  - PR: `gh pr view <N> --json title,body,baseRefName,headRefName,mergedAt,files` and `gh pr diff <N>`. If the PR is merged, `git log --merges` or the merge commit gives the post-merge tree; read the current code for the surrounding context, and note in the report if it has drifted since the merge.
  - Branch: `git merge-base <default> <branch>` then `git diff <base>..<branch>`.
  - Session implementation: the files changed in this session and the decisions made in the conversation, including alternatives you rejected and limitations you noted.
  - Repository: the tree, entry points, `README`, `AGENTS.md` or `CLAUDE.md`, and the main data path from input to output.
  - Path: the file or directory plus its callers and callees one hop out.
- 0.3 When the scope is large (a repository with thousands of files), choose the layer that matters: entry points, core modules, the main flow, the places most changes land. Record what was left out for the coverage line in Phase 4.

## Phase 1: Study and build the answer key

- 1.1 Read the scope. For a diff, also read enough surrounding code to know what the change interacts with, because the interesting questions live at the boundary. For broad repositories, collect concept candidates with `path:line` evidence before writing questions.
- 1.2 Extract concepts across these categories. Cover at least four of the six when `n` is 6 or more:
  - Structure: what lives where, and why the split exists.
  - Flow: how a request, event, or piece of data travels through the scope, in order.
  - Decisions: why this design and not the obvious alternative; which tradeoff was taken.
  - Contracts: invariants, what callers must guarantee, what the code guarantees back, what is assumed about the environment.
  - Failure: what happens on bad input, timeout, concurrency, or missing config; what fails loudly and what fails silently.
  - Change impact: to add feature X or fix bug Y, which places change and which do not.
- 1.3 For a session implementation, the concepts also include the decisions you made, the alternatives you did not take, and the known limitations. Litt's point applies most to code the user did not write themselves.
- 1.4 Write the key privately:

```
KEY = [{
  id, category, concept,
  difficulty: 1 | 2 | 3,        # 1 recall of structure or flow, 2 decisions and contracts, 3 failure or change impact composed from two facts
  format: "predict" | "locate" | "why" | "impact" | "order" | "explain",
  question, options[], correct,  # options omitted for "explain"
  why_wrong: {option: reason},   # one sentence per distractor
  evidence: "path:line"
}]
```

Write `n` primary entries plus about 30 percent spare entries for retests (R7). Order primaries from difficulty 1 to 3 with categories interleaved. With `--hard`, drop difficulty 1.

## Phase 2: Ask in rounds

- Round size: 2 questions, or 3 when `n` is 10 or more. One AskUserQuestion call per round.
- `header`: the category ("Flow", "Decision", "Failure", "Impact").
- `question`: self-contained. Quote the relevant snippet inline (at most 10 lines) when the answer depends on it, because the user may not have the file open. Name the file so they can look.
- `options`: 2-3 substantive options plus "Not sure". `multiSelect: true` for change-impact questions where several places change. `preview` when options are code shapes, outputs, or orderings.
- Formats, rotated so no two consecutive questions share one:
  - Predict: "Given input X, what does this return, or what happens?"
  - Locate: "A user reports Y. Which of these is the cause?"
  - Why: "Why does the code do X instead of Y?"
  - Impact: "To add Z, which of these must change?"
  - Order: "Which ordering matches what actually runs?"
  - Explain: a short-answer question asked in plain prose, waiting for the user's reply. At most 2 per quiz. Use it for the concept that matters most, because guessing is impossible.
- Grade each round (Phase 3) before asking the next one. Insert a retest for any miss or "Not sure" at least one round later, using a spare entry on the same concept or a new entry written from a different angle.

## Phase 3: Grade and give feedback

After each round, for each question:

```
Q3 (Flow): correct | missed | not sure
Answer: <correct option>. <one sentence why>. Evidence: <path:line>
Why "<chosen option>" is tempting: <one sentence>        (misses only)
Missing: <the part a partial answer left out>              (explain questions only)
```

Keep this to a few lines per question. The full explanation is available on request after the quiz; during it, the evidence pointer is enough.

## Phase 4: Report

```
## Quiz: <scope>   <hits>/<n>   <pass | not yet>

| # | category | concept | result | retest |
|---|---|---|---|---|

Gaps, in reading order
- <concept>: <path:line>. <what to look for, one sentence>

Solid
- <categories or concepts with every question right, including retests>

Coverage
- <what the quiz covered, and what in scope it did not touch>
```

Pass means 80 percent or more, with every retest answered correctly. Then offer, in one line each: retake the gaps only, go deeper on one area, or get an explanation of a gap. An explanation follows Litt's explainer shape: background and intuition first, then the goal, then the code, as a narrative rather than a file-by-file walk.

## Question craft

| bad | why | good |
|---|---|---|
| "What is the name of the function that parses config?" | trivia | "Config is read at startup and again on reload. Which is true: the second read replaces the first entirely / keys missing from the second read keep their first value / env vars override both reads?" |
| three absurd options and one right one | no misconception is tested | options that are each true somewhere else in this codebase but false here |
| a question the PR title answers | tests reading, not understanding | a question about what the PR had to change beyond the obvious file, and why |
| a question about a detail you did not verify | violates R1 | verify it or cut it |
| "Do you understand the caching?" | yes or no, no signal | "A request arrives 2 seconds after an identical one. Which path runs?" |

Difficulty ladder: 1 is recall of structure or flow, 2 is decisions and contracts, 3 is failure and change impact that require composing two facts. A quiz with only level 1 questions passes skimmers; a quiz with only level 3 questions teaches nothing about where the gap starts.

## Notes for the operator (you)

- N1. "Skip" is a "Not sure". Mark it, move on, retest later.
- N2. When the user disputes a grade, re-read the evidence. If they are right, fix the grade and the score and say so. If not, quote the line.
- N3. The main use is self-testing after the user believes they understand. Do not lecture before the quiz; explanation arrives with the grade or on request afterward.
- N4. For a session implementation, do not soften questions about your own limitations. The most valuable question is often "what does this code not handle?"
- N5. Without an interactive answer channel (a non-interactive run), do not run the quiz. Say so and stop.
- N6. Two quizzes on the same scope should not repeat questions. If the conversation shows an earlier quiz, write new entries and lean on the earlier gaps.
