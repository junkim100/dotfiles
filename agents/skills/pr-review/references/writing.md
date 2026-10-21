# Writing inline comments

Read this before Phase 7.4. The goal is a body the user can post unchanged. In the study behind this skill, only about a third of drafts were already in their final wording, and most edits were the same few corrections: softer endings, fewer rule labels, shorter removal requests, plainer words, and claims narrowed to what was shown. The house rules (G2 to G7) are binding; this file shows how to apply them.

If `~/.local/state/pr-review/examples.md` exists, read it too. It holds real comments the user posted unchanged and comments by a reviewer whose style the user wants to match. It is private: never copy its content into this skill, a commit, or any public file.

## Shape

1. Mechanism, anchored: what the code does, with `path:line`. Lead with the fact, not with "I think" or a summary of the PR.
2. Trigger and consequence: the concrete input or state, and what goes wrong for whom (a wrong score, a lost artifact, a crash that takes other work with it, misleading metadata). Say how you know when it matters (`실행해서 확인했습니다`, a reproducing input).
3. The ask: the fix when it is not obvious, or a question when the decision belongs to the author.

Usually 2 to 3 sentences. Length follows the evidence: a compound-state bug may need a short code excerpt or a sibling reference, and a removal request needs one sentence. Never pad to look thorough, and never cut the consequence to look short.

## Moves that make a comment land

- Bound the claim. When current inputs are fine but the contract allows a breaking one, say both: `지금 데이터는 task당 record가 하나라 값이 맞지만, ~하면 ~가 들어갈 것 같습니다.` This keeps a true finding precise without overstating it.
- Name the real consumer. `reader가 아직 0~1 비율로 읽어서 38.2 같은 값이 들어오면 막대가 그려지지 않을 것 같습니다` beats "단위가 일관되지 않습니다".
- Offer a sibling's remedy only after checking it handles the same mechanism, and point at it with `path:line`.
- Ask whether a test could fail for the bug when a test is cited as coverage: `이 test의 fixture에는 중간 응답에 text가 없어서 이 경우를 잡지 못할 것 같습니다.`
- Questions carry the diagnosis. Verify the facts first, put them in the question, and leave the decision with the author: fact, pinned permalink, `혹시 ~한 이유가 있었을까요?`, conditional fix.
- One comment per fix site. Several symptoms with one fix share a comment; one finding whose parts need fixes in different files becomes several comments.

## Examples (synthetic; names are illustrative)

Consumer mismatch:

> 새 breakdown score를 percent로 싣고 있는데요, `reports/chart_reader.py:118`은 아직 0~1 비율로 읽어서 38.2 같은 값이 들어오면 group별 막대가 하나도 그려지지 않을 것 같습니다. headline 쪽(`chart_reader.py:96`)처럼 `score_unit`을 보고 값을 그대로 쓰도록 맞춰야 할 것 같습니다.

Compound state, verified by execution:

> `if tool_calls:` 분기(`agent/loop.py:84`)가 `stop_reason` 검사(`:97`)보다 먼저 실행되어, `max_tokens`로 잘린 응답에 tool call이 섞여 있으면 잘린 `input`으로 tool이 실행되고 truncation은 기록되지 않습니다(stub 응답으로 실행해서 확인했습니다). truncation 검사를 tool 분기 앞으로 옮겨야 할 것 같습니다.

Recorded value differs from the value sent:

> result record의 `reasoning_effort`는 spec 값(`runner.py:212`)을 그대로 싣는데, 실제 요청에는 profile을 먼저 보고 spec을 fallback으로 쓰는 `effective_effort`(`runner.py:140`)가 들어갑니다. spec이 null이고 profile에 값이 있는 run에서는 record에 null이 남으므로 실제 적용한 값을 기록해야 할 것 같습니다.

Value differs from a pinned source (question with conditional fix):

> upstream `scripts/run.sh`의 per-task timeout은 이 config가 pin한 revision 기준 1800입니다([permalink](https://github.com/<org>/<repo>/blob/<pin>/scripts/run.sh#L24)). 1800이 아니라 2000으로 두신 이유가 있었을까요? 특별한 이유가 없다면 1800으로 맞추고 test의 값도 같이 바꿔야 할 것 같습니다.

Bounded claim:

> `rows_loaded`를 record 수로 읽는 조건에 `items_per_task == 1`이 들어 있는데요, 반복 횟수를 따로 세는 multi-trial harness가 이 값을 싣기 시작하면 trial 수 대신 task 수가 들어갈 것 같습니다. 지금 이 값을 싣는 module은 task당 record가 하나라 당장 틀린 값은 없지만, 전체 record 수와 같을 때만 record 수로 읽는 것이 안전할 것 같습니다.

Unchanged code whose consequence changed:

> 이번 변경으로 scratch를 항상 지우게 되면서, 채점하지 않는 job의 최종 snapshot도 받은 직후 바로 지워집니다(`worker.py:402`). 이전에는 디버깅용으로 남았지만 이제는 시간과 디스크만 쓰므로, snapshot 호출을 채점 분기(`worker.py:417`) 안으로 옮기는 것이 어떨까요?

Removal:

> 이 파일은 삭제해야 할 것 같습니다.

Follow-up reminder:

> 대부분 반영해 주셨고 두 곳만 남은 것 같습니다. `cli.py:88`의 `--timeout` help가 아직 3600s로 되어 있는데 실제 default는 7200s이고, `backends.py:40` docstring에 이전 동작 설명이 남아 있습니다.

## Anti-examples

- Outsourcing a check: `혹시 이 provider 이름이 고정된 값인지 확인 부탁드립니다.` A grep answers it (R6). Check, then either drop it or state the finding.
- Rule decoration: `GUIDELINE P4에 따라 ...` when the problem and consequence already make the case (G2).
- Restating what is right: `다른 config는 이미 갱신돼 있습니다. 다만 ...` (G3).
- A bundle: one comment carrying many unrelated issues hides priority. Split by fix site, and hold the low-value ones.
- An unbounded claim: `이 경로는 항상 실패합니다` when it fails only for one provider. Name the condition.
- Speculation without a mechanism: `혹시 성능 문제가 있을 수도 있을 것 같습니다.` No trigger, no consequence, no comment.
- Platform portability in a Linux-only repository (house rule W1).
