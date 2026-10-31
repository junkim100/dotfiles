# Writing references

Use the user's own populated sections from the preceding 4-8 weeks as the format reference for every run. Search the live meeting series relative to the requested report, read those sections, and give recent recurring patterns the most weight. The links below are a verified starting set, not a permanent substitute for fresh discovery. They are writing samples, not evidence for a later week's accomplishments, and none is a default destination.

## Samples checked

On October 16, 2026, the `Eval TODOs` data source returned eight weekly pages dated August 21 through October 9 for the preceding two-month window. Seven contained Jun's populated entry; the October 9 page contained only his mention, an empty block, and an empty `[Skill Lab Related]` heading, so it is excluded as a style example. Dates below are the pages' `Created Date` values, not assumed boundaries of the work reported inside them.

| Page date and source | Format observed in Jun's section |
| --- | --- |
| [October 2](https://app.notion.com/p/3ede45d0002581f5b2a7dcf94f5d6c26) | Blue-background topic headings; current engineering workstreams first and PR reviews last; DONE/WIP within topics; before/after score table; technical sub-bullets; research meeting notes without a status label |
| [September 25](https://app.notion.com/p/3e6e45d0002581c5ac53df63042911f5) | Policy decisions, implementation progress, and result analysis grouped by workstream; concrete counts and caveats; separate Skill Lab and PR review sections |
| [September 18](https://app.notion.com/p/3dfe45d0002581108f5ecbfeae79b69a) | Blue-background headings; error-treatment comparison table; nested concrete examples, review responses, run settings, failures, and next steps |
| [September 11](https://app.notion.com/p/3d8e45d000258194afeec7c4d0fa7204) | Blue-background headings; model/result and sanity-check tables; benchmark settings, measured costs and limitations; a collapsed Q&A toggle under a study item |
| [September 4](https://app.notion.com/p/3d1e45d00025815cbda7f2876c11972d) | Blue-background topic headings; DONE/WIP groups; PR, resource planning, research, Skill Lab, and ETC workstreams |
| [August 28](https://app.notion.com/p/3cae45d0002581a28c05d36b7517758e) | Flatter DONE/WIP groups followed by Skill Lab; benchmark-level migration and sanity-check states, numeric comparisons, and blockers |
| [August 21](https://app.notion.com/p/3c3e45d00025810d9a43e88ee3303626) | Bold bracketed topic headings; DONE/WIP within PR reviews; unlabelled research and Skill Lab narrative bullets |

All seven extracted personal sections had explicit section boundaries and no unknown blocks inside them. Some full-page fetches flagged unknown blocks elsewhere; those parts were not used to infer Jun's style.

The user's original explicit anchors remain useful navigation hints:

- [September 4 meeting, user's linked section](https://app.notion.com/p/upstage/LLM-Evaluation-Weekly-Meeting-3d1e45d00025815cbda7f2876c11972d?source=copy_link#6dee45d000258299ab5501fcce94100e)
- [August 28 meeting, user's linked section](https://app.notion.com/p/upstage/LLM-Evaluation-Weekly-Meeting-3cae45d0002581a28c05d36b7517758e?source=copy_link#9a9e45d00025823786bd81eac6773c3e)

## Observed style

The author's display name in these samples is `Jun(김동준)`, confirmed through Notion's user lookup. Locate that person's section under `Weekly Progress`; it is not the first contributor's section. Re-resolve the identity if the connected workspace or author changes.

The recurring recent format is Korean progress notes with English benchmark and system names, fourth-level bracketed topic headings with a blue background, and bold `[DONE]` / `[WIP]` groups inside each topic where useful. Headings name actual workstreams, such as `[벤치마크 에러 샘플 처리]`, `[벤치마크 평가 로그 통합 수집 파이프라인]`, `[산학과제: Degeneration Research]`, `[PR 리뷰]`, or `[Skill Lab Related]`. Research or coordination notes can appear directly under a topic without a status label. The older August entries use bold headings and sometimes a flatter list; prefer the recurring recent form unless the user requests otherwise.

Order topics to fit the week's work. PR reviews often appear first in older entries, but the September 25 and October 2 entries lead with the main engineering or analysis workstreams and place PR reviews later. Do not force a fixed topic order or include an empty Skill Lab section just because the page template contains one.

Lead each bullet with the task and concrete action or result. Typical endings include `리뷰 및 승인 완료`, `merge 완료`, `코멘트 대응`, `진행 중`, and `결과 공유`. Write a merged PR as `merge 완료`, never `main 머지` (the user's explicit preference). Only use those verbs when supported. Put the PR link, native Notion mention, or Slack reference on the task bullet where practical. Use a PR link labeled `#1234` rather than repeating its whole title or URL. Inline code marks commands, parameters, paths, models, and schema fields when their exact spelling matters.

Keep routine PR updates short, but give substantial investigations enough detail to be useful: what changed or was discovered, how it was checked, numeric results with settings and denominators, limitations, and remaining work. One or two levels of indented bullets are common, with deeper examples when needed. Do not reduce a major workstream to a one-line summary or impose a fixed bullet cap.

Use compact tables for genuinely comparative evidence, as in the model calibration, official-versus-local sanity check, error-policy matrix, and before/after headline-score examples. Keep units, sample counts, settings, and important caveats adjacent. Use a toggle for optional detailed material such as the September 11 study Q&A, not as a requirement for every topic. Build these blocks using the current Notion Markdown contract.

Keep related implementation, review, and verification details together. Do not turn the report into a chronological activity log, an executive summary, or a list of agent sessions. Match the user's level of specificity without copying stale statuses: one sample has completed merge bullets beneath a WIP heading, which is a historical inconsistency to resolve from fresh evidence, not a convention to reproduce.

Preserve the person's native mention and surrounding page structure. Read the current Notion Markdown specification before recreating colored headings or native mentions; this is only a plain Markdown sketch with illustrative placeholders, not publishable content:

```markdown
#### [PR 리뷰]

**[DONE]**

- {벤치마크} PR 리뷰 및 승인 완료 {PR 링크}
  - {주요 확인 사항 또는 수정 결과}

#### [Skill Lab Related]

**[WIP]**

- {벤치마크} migration PR 코멘트 대응 {PR 링크}
  - {검증된 현재 상태}
  - {남은 작업 또는 blocker}
```

The sketch illustrates only the basic nesting; it is not a maximum length or a requirement to add status labels to research notes. No mandatory category or bullet count. Add research, resource planning, infrastructure, or other workstream headings when supported. Keep one logical line per paragraph or list item. Do not use em dashes or en dashes.

## Finding the next set of examples

Start from the destination page's parent data source and fetch its current schema. The verified series is in `Eval TODOs` (`collection://2f3e45d0-0025-80aa-9a8f-000b095aadb4`), with weekly titles `LLM Evaluation Weekly Meeting` and a `Created Date` property; re-resolve these if the workspace structure changes. Search or query a 4-8 week window before the requested report, then fetch the actual pages and extract Jun's sections. Do not use search snippets or page timestamps alone as writing samples. Keep the sample URLs and populated/empty distinction in the task evidence. If the series is inaccessible, use the verified examples above and report that fresh style sampling was unavailable.

## Wiki orientation

The skill was informed by `eval-wiki/wiki/weekly-meeting-logs.md`, its linked `eval-wiki/wiki/raw-source-status.md`, and `eval-wiki/wiki/repo/files/AGENTS.md.md`, checked against the repository's actual `AGENTS.md` and the live Notion samples above. The useful consequences are to fetch the live requested page, account for incomplete imported sources, and verify status from primary evidence. Consult current versions when running the skill; these notes do not replace the mandatory wiki lookup.
