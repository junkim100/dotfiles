---
name: paper-study-notes
description: Turn an academic paper into reading-group teaching notes - a bulleted, example-dense reconstruction built to be presented from, not read silently. Use this skill whenever the user gives a paper title, arXiv link, or PDF and wants to prepare to present it, teach it to a study group, walk a team through it, or make structured study notes - even if they just say "make notes on this paper," "help me present X," "summarize this for our reading group," or paste a link and ask what it says. Triggers on requests to study, present, or deeply digest a specific paper, not on quick one-line factual lookups.
---

# Paper Study Notes

Produce **study-group teaching notes** for a single paper: a reconstruction of the paper's *argument* that someone can stand up and present from. This is deliberately different from an abstract or a neutral summary.

The output is always a Markdown file, in **English**, and it is **bulleted and tabular, never flowing prose**.

## What makes these notes different

Three properties define the format. If the output loses any of them, it has failed.

1. **It reconstructs the argument, not the table of contents.** The spine is always: *why does this exist → what exactly did they build → how do they measure it → what did they find → where does it break.* A reader should come away understanding the paper's logic, not just its components.
1. **Concreteness over completeness.** Real counts, real category lists, at least one task/example quoted verbatim, the headline result numbers called out. The single most common way these notes go wrong is vagueness ("they evaluate several models on a range of tasks"). Hunt down the specifics. Note: surface a paper's *results* by pulling the headline numbers inline and **referencing the table as a `[Table N]` to paste - don't retype it** (retyping duplicates the pasted image and invites transcription errors).
1. **It is built to be spoken from.** Bullets, tables, and figure/table placeholders that name the specific exhibit to paste - `[Figure 1: ...]`, `[Table 3: ...]` - wherever a figure or results table from the paper belongs. The presenter pastes the images; the notes carry everything else and point to exactly which figure or table goes where.

Three more habits that make the notes feel expert rather than mechanical:

- **Walk the motivating example to a punchline.** When a paper has a concrete scenario showing why its gap matters, don't compress it to one line - walk it (often as nested bullets contrasting two outcomes) and land on the takeaway it motivates ("…which is why they measure X"). This is usually the most memorable part of the notes.
- **Connect each mechanism to its motivation.** Don't just state what they did - say why. ("They use deterministic environment-state checks instead of an LLM judge *because* a successful prompt injection could also hijack the judge.")
- **Cross-reference sibling work** where natural - predecessors, follow-ups, and competing benchmarks - so the paper sits in a lineage rather than in isolation.

## Workflow

Use the current agent's available file, PDF, and web tools. Resolve bundled references relative to this `SKILL.md`. Use the user's requested output directory, or `outputs/` in the current workspace when none is specified, and return a link to the resulting file.

### Step 1 - Resolve and read the full paper

The input arrives in one of three forms; handle whichever applies:

- **An uploaded file**: read the supplied local path. Use an available PDF-reading tool or skill, or extract its full text and inspect its figures and tables. Don't go to the web for a paper you already have in hand.
- **A link**: fetch it with an available web or download tool. If it's an arXiv abstract page, fetch the PDF (`arxiv.org/pdf/<id>`) to get the full body.
- **A title only**: search the web for it, find the arXiv (or other) page, then fetch the PDF surfaced by search.

Either way, work from the **full text**, never the abstract alone - these notes live or die on details that only appear in the body, tables, and appendices. Read the whole thing: dataset construction, exact numbers, the main results table, ablations, and the paper's own stated limitations. Note the venue and year, authors, affiliation, and any code/dataset link. For a long paper, prioritize the sections that map to the notes - motivation, the dataset or method, the main results table, and limitations - over absorbing every paragraph. Papers also live on OpenReview, the ACL Anthology, or journal sites; the rule is the same - get the full text, not a landing page.

### Step 2 - Extract the specifics

Before writing, pull out:

- **Positioning** - where does this paper sit in its lineage? Is it the first of its kind, a fix to a known problem, a scaling-up, a new threat model? This becomes the opening line.
- **The gap** - what prior approaches couldn't do, stated concretely. Often the most useful single thing to nail.
- **A motivating example** - many papers have a concrete scenario that shows *why the gap matters*. If one exists, capture it; a worked example in the intro is worth a paragraph of abstraction.
- **Dataset/method specifics** - exact counts, category lists, task structure, and **at least one example quoted verbatim** (a real task prompt, input, or sample).
- **Metric definitions** - define each metric precisely, in the paper's terms.
- **Results** - the headline numbers to call out inline, plus which figures/tables to paste. Capture the interesting breakdowns/ablations too, not just the top-line score. Don't plan to retype results tables - note them as `[Table N]` to paste.
- **Figure/table numbers** - note the actual numbers and captions of the teaser and the main-results exhibits, so the placeholders point to the right thing. If you only have an HTML version where numbering is ambiguous, check the PDF.
- **Limitations** - the paper's own, plus any obvious ones, plus follow-up papers if you know them.

If a specific number or example can't be found in the source, write `[verify]` next to your best guess rather than inventing it. Never fabricate counts, quotes, or results. The same applies to lineage: cross-reference only papers you actually know - don't invent predecessors, follow-ups, or a comparison to make the notes look connected.

### Step 3 - Write the notes

Read `references/template.md` for the skeleton and the example matching your paper's archetype - `references/example.md` (benchmark) or `references/example-method.md` (method). Follow the template's structure, adapt the section labels to the paper's type (see "Adapting the spine to the paper type" below), and match the example's density and register.

### Step 4 - Save and present

Write `<short-paper-name>-study-notes.md` in the chosen output directory and link to it. Keep any closing message short; the notes are the deliverable.

## Output structure

The **four-beat spine is fixed**; the **section labels adapt** to the paper type. A benchmark paper, a method paper, and a theory paper populate the middle differently - use whatever labels fit, but preserve the logical flow.

```
# <N>. <Short Name> (<Venue Year>)
**<Full Paper Title>**
- <Authors, affiliation>
- <arXiv / paper link>
- <code or dataset link>

## 0. Intro
[Figure 1: <teaser - the diagram that captures the paper at a glance>]
- <one-line positioning in the lineage>
- Limitations of prior work
    - <each gap, explained - not just named>
    - <optional: a concrete worked example showing why the gap matters>
- What <Name> does differently  (or: Key ideas)
    - <each contribution>

## 1. <Dataset / Benchmark / Setup / Approach>   <- "what they built"
### <Tasks / Data / Components>
- <exact counts, category lists, structure>
### <Sub-breakdown: e.g. Tools, Environments, Examples>
- <real quoted example(s) + tables>

## 2. <Methodology / Evaluation>   <- "how they measure / how it works"
### Metrics
- <each metric defined precisely>
### <Mechanisms: Attacks / Defenses / Judge / Training / etc.>
- <how it works AND why>
### <Validation, if the paper has it>

## 3. Results
- <numbered key findings>
- <headline numbers called out inline; mark [verify] if not yet confirmed>
[Table N: <the paper's main results table - pasted, not retyped>]
- <breakdowns / ablations worth noting>

## 4. Limitations   (+ follow-up work if relevant)
- <each limitation, paper-sourced where possible - terse is fine>
```

## Adapting the spine to the paper type

The four beats (§0 → §4) are universal; what changes is **what §1 and §2 are called and contain**. Decide the archetype by asking: *what is this paper's primary contribution?* Then use the matching labels.

- **Benchmark / dataset** (e.g. AgentHarm - see `references/example.md`): §1 = **Dataset / Benchmark** (tasks, exact counts, a verbatim sample); §2 = **Methodology / Evaluation** (metrics, attacks/defenses, the judge and how it's validated).
- **Method / model** (a new technique, architecture, training recipe, or agent scaffold - e.g. ReAct, see `references/example-method.md`): §1 = **Method / Approach** (the core idea, the algorithm or loop, the components; the verbatim "example" is a worked trace, a key prompt, or an equation - *not* a dataset sample); §2 = **Experiments** (the benchmarks they run on - usually *others'*, not theirs - baselines, and setup). The "what they built" in §0 is the *idea*.
- **Empirical / analysis** (measures or explains a phenomenon): §1 = **Setup** (what's measured, models/data, experimental design); §2 = **Findings** - here the results *are* the contribution, so this often merges with §3.
- **Theory** (a formal result): §1 = **Setup / Definitions** (formalism, assumptions); §2 = **Main results** (theorem statements + proof intuition). Replace results tables with the key claims and what they imply.
- **Survey / position**: §1 = **Taxonomy** (the organizing structure of the field); §2 = **Per-axis synthesis**; the "Results" slot becomes **Open problems / where the field is heading**.

When a paper blends types, pick the dominant one and borrow a sub-section from another if needed. The mistake to avoid is forcing benchmark labels ("Dataset," "Tasks") onto a paper that has none.

## Multi-paper study pages

A common request - a reading-group page covering several related papers (a survey of a subfield, a comparison of competing approaches). Assemble it like this:

1. **Shared intro on top** - the thesis that ties the papers together (the trend, tension, or question they collectively address), plus a small table positioning each paper (one row per paper: *what it is / its angle / why it's here*).
1. **One full per-paper block for each** (the entire single-paper structure above), numbered `# 1.`, `# 2.`, … in a deliberate order (chronological, or grouped by theme).
1. **A side-by-side comparison table near the end** - one row per dimension (e.g. scope, environment, scale, method, key metric, key finding, limitation), one column per paper. This is usually the single highest-value artifact for the audience.
1. **A "Takeaways & Discussion" close** - the cross-paper patterns drawn together, plus a few open questions to seed discussion.

Keep cross-references flowing between the blocks ("same execution-based scoring as paper 1") so the page reads as one argument, not a stack of summaries.

## Style rules

These are hard constraints, in rough priority order:

- **English by default.** Write the notes in English regardless of the paper's language or the surrounding context - *unless the user asks for another language* (including the source paper's or their own notes' language), in which case follow that.
- **Bullets and tables, not prose.** No multi-sentence paragraphs. Each bullet is one idea; nest for detail.
- **Real numbers and real examples.** Quote at least one task/sample verbatim (use bold sub-labels + blockquotes when contrasting, e.g. **Harmful** / **Benign**). Call out the headline result numbers inline. Specifics are the whole point.
- **Numbered figure/table placeholders** for every exhibit the presenter should paste, naming the specific one: `[Figure N: <what it shows>]` or `[Table N: <what it shows>]`. Use the paper's actual figure/table numbers; if a number genuinely can't be determined, fall back to `[Figure: <description>]`. Include at minimum the teaser in §0 and the main results in §3.
- **Paste results, don't retype them.** A paper's own results table is referenced as a `[Table N: ...]` placeholder with the headline numbers pulled inline - never retyped as markdown. **Type a markdown table only for information you are *synthesizing*** (a cross-paper comparison, or a small overview of a benchmark's structure) where no single source image captures it.
- **Scale depth to the paper.** A 4-page workshop paper gets tighter notes than a 40-page one. Drop sub-sections that don't apply rather than padding to fill the template.
- **Mechanism → motivation.** Pair what with why.
- **Cross-reference** predecessors, follow-ups, and rivals where it adds context - but only ones you actually know; never invent a lineage to look connected.
- **Teaching register** - concise, direct, the voice of someone who has read it and is about to explain it. Light positioning metaphors are welcome ("the ur-benchmark for X," "the progenitor of this line"). Avoid hedging and filler.
- **Don't fabricate.** Mark uncertain values `[verify]`.

## Quality checklist

Before presenting, confirm:

- [ ] Could a reader reconstruct the paper's *argument* (gap → build → measure → find → limits) from these notes alone?
- [ ] Does the §0 motivating example (if any) walk to a punchline rather than sitting as one line?
- [ ] Is there at least one verbatim example from the paper?
- [ ] Are the headline result numbers called out inline, with the paper's results table referenced as a `[Table N: ...]` to paste (not retyped)?
- [ ] Are typed markdown tables used only for *synthesized* comparisons, not reproductions of a paper's own table?
- [ ] Is every mechanism paired with its motivation?
- [ ] Are numbered figure/table placeholders (e.g. `[Figure 1: ...]`) present for the teaser and the main results, each naming the specific exhibit?
- [ ] Is it all bullets/tables - zero prose paragraphs?
- [ ] Is it in the right language (English by default, or whatever the user asked for)?
- [ ] Are any unverified numbers marked `[verify]` rather than asserted?

## Reference files

- `references/template.md` - the annotated blank skeleton (with a method-paper variant at the bottom). Read this first when drafting.
- `references/example.md` - the canonical example, **benchmark / dataset** archetype (AgentHarm). Shows the target style end to end: pasted (not retyped) results, a multi-level §0 worked example, org-level byline, verbatim Harmful/Benign contrast.
- `references/example-method.md` - a filled example for the **method / model** archetype (ReAct): how §1 becomes "Method" and §2 runs on others' benchmarks.
