<!--
ANNOTATED TEMPLATE for paper study notes.
Copy this skeleton and fill it in. Replace every <...> placeholder.
HTML comments like this one are guidance - delete them in the final output.
The four-beat spine (0 Intro / 1 what they built / 2 how they measure / 3 results / 4 limits)
is fixed. The section LABELS adapt to the paper - rename §1 and §2 to fit.
Keep everything in English. Bullets and tables only - no prose paragraphs.
-->

# <N>. <Short Name> (<Venue Year>)

**<Full Paper Title>**

- <Labs / orgs behind it, and/or key authors - e.g. "Gray Swan AI + UK AI Safety Institute" or "Yao et al., Princeton + Google">
- <arXiv or paper URL>
- <code / dataset URL, e.g. GitHub or HF>

## 0. Intro

[Figure 1: <teaser - the diagram that captures the whole paper at a glance>]
<!-- Name the paper's actual figure/table. Use [Table N: ...] for a table.
     If the number genuinely can't be determined, fall back to [Figure: ...]. -->

- <ONE-LINE POSITIONING: where this sits in the lineage. e.g. "The first benchmark to measure X," "A fix for the contamination problem in Y," "Scales Z from 12 repos to 41." A light metaphor is fine: "the ur-benchmark for X," "the progenitor of this line.">
- Limitations of prior work
    - <GAP 1 - stated concretely, not just named. What couldn't prior work do, and why does that matter?>
    - <GAP 2 ...>
    - <OPTIONAL but high-value: a concrete worked example that shows why the gap bites. A single vivid scenario beats a paragraph of abstraction.>
- What <Name> does differently
    <!-- some authors call this "Key ideas" or "Contributions" - use whatever fits -->
    - <CONTRIBUTION 1>
    - <CONTRIBUTION 2>
    - <CONTRIBUTION 3>

## 1. <Dataset / Benchmark / Setup / Approach>
<!-- "WHAT THEY BUILT." Rename to fit: Dataset for a benchmark paper, Approach/Method
     for a method paper, Setup for an environment paper. -->

### <Tasks / Data / Components>

- <EXACT counts. How many tasks/examples/instances? How are they split (train/val/test, public/private)?>
- <Category list - name the actual categories, don't say "several categories">
- <Structure - how is each item composed? augmentations? pairs?>

### <Sub-breakdown - e.g. Tools / Environments / Benign pairs / Input format>
<!-- Add as many ### sub-sections as the paper warrants. This is where verbatim examples go.
     For contrasting examples, use bold sub-labels + blockquotes (see the Harmful/Benign
     pattern in references/example.md). -->

- <Detail with a REAL QUOTED EXAMPLE from the paper - an actual task prompt, input, or sample. Block-quote it so it stands out.>

  **<Label A, e.g. Harmful>**

  > <verbatim example text from the paper>

  **<Label B, e.g. Benign>**

  > <verbatim contrasting example, if the paper pairs them>

- <Type a markdown table ONLY for a small structural overview you are synthesizing (e.g. a per-suite breakdown), NOT for reproducing the paper's results table:>

| <col> | <col> | <col> |
| --- | --- | --- |
| <...> | <...> | <...> |

## 2. <Methodology / Evaluation>
<!-- "HOW THEY MEASURE / HOW IT WORKS." -->

### Metrics

- **<Metric 1>**: <precise definition in the paper's terms - what exactly is counted?>
- **<Metric 2>**: <...>

### <Mechanisms - e.g. Attacks / Defenses / Jailbreaks / Judge / Training procedure>
<!-- Whatever moving parts the paper has. ALWAYS pair what with why. -->

- <MECHANISM - how it works, AND the reason the authors chose it. e.g. "Deterministic env-state checks instead of an LLM judge - because a successful injection could otherwise hijack the judge too.">

### <Validation - only if the paper validates its own measurement>
<!-- e.g. "Do we trust the judge?" - agreement with human labels, F1, etc. Many papers
     that introduce an automated judge or evaluator include this; capture it. -->

- <How the measurement itself was checked, and the numbers (agreement / F1 / etc.).>

## 3. Results

- <KEY FINDING 1 - numbered findings read well for presenting>
- <KEY FINDING 2 ...>
- <Headline numbers called out inline, e.g. "harm score 48.4% → 72.7%". Mark [verify] if not yet confirmed against the paper.>

[Table N: <the paper's main results table - PASTE it, do not retype it>]

- <Breakdowns / ablations - the interesting second-order results, not just the top line. e.g. per-category, per-difficulty, attacker-knowledge, with/without a component.>


## 4. Limitations
<!-- + follow-up work if relevant -->

- <LIMITATION 1 - prefer the paper's own stated limitations; add obvious ones too.>
- <LIMITATION 2 ...>
- <OPTIONAL: follow-up papers that extend or fix this one, one line each.>


<!--
==================================================================================
VARIANT: §1 and §2 for a METHOD / MODEL paper (a new technique, not a dataset).
Swap these in for the §1/§2 above when the paper's contribution is a method.
See references/example-method.md (ReAct) for a filled version.
==================================================================================

## 1. Method   (or: Approach)
### <The core idea>
- <the central mechanism, stated plainly - what is new and why it works>
### <The algorithm / loop / architecture>
- <step-by-step or component-by-component; pseudocode-level if useful>
- <verbatim "example" here is a worked trace, key prompt, or equation - NOT a dataset sample>

  > <verbatim trace / prompt / equation from the paper>

### <Design choices / why it's attractive - the authors' framing>
- <each property + the reason it matters>

## 2. Experiments   (or: Evaluation)
### Setup
- <benchmarks used - usually OTHERS', not theirs; name them>
- <baselines, and how they were constructed (often by ablating the method)>
- <any training/finetuning regime>
-->
