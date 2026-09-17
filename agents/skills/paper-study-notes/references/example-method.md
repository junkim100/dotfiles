<!--
GOLD-STANDARD EXAMPLE #2 - the METHOD / MODEL archetype (a new technique, not a dataset).
Contrast with example.md (the BENCHMARK archetype). Note how §1 becomes "Method" (the idea,
not a dataset), §2 becomes "Experiments" run on OTHERS' benchmarks, and the verbatim example
is an action-space spec / trajectory rather than a dataset sample.
-->

# ReAct (ICLR 2023)

**ReAct: Synergizing Reasoning and Acting in Language Models**

- Yao, Zhao, Yu, Du, Shafran, Narasimhan, Cao - Princeton + Google Research (Brain)
- https://arxiv.org/abs/2210.03629
- https://react-lm.github.io/ · https://github.com/ysymyth/ReAct

## 0. Intro

[Figure 1: the four prompting styles - Standard / CoT (reason-only) / Act-only / ReAct - on a HotpotQA question, plus an ALFWorld trajectory]

- Widely treated as the progenitor of the modern LLM-agent loop (thought → action → observation). It's a **prompting paradigm**, not a new model and not a dataset.
- Limitations of prior work
  - **Reasoning-only (CoT)** is a static black box: the model reasons from its own internal state with no grounding in the world, so it can't reactively check or update knowledge → fact hallucination and error propagation.
  - **Acting-only** planners (WebGPT-style) map context → actions but don't reason abstractly about high-level goals or keep a working memory over long horizons.
  - Nobody had combined the two **synergistically** for general task solving, or shown the combination yields systematic benefits over either alone.
  - Motivating example (the paper's own): cooking. Between actions you reason ("everything's cut, now heat the water"), handle exceptions ("no salt - use soy sauce and pepper"), and notice when you need outside info ("how do I prepare dough? let me search"). Reasoning and acting interleave naturally.
- Key idea
  - **Augment the action space from A to Â = A ∪ L**, where L is free-form language. A "thought" (an action in L) changes nothing in the environment - it just composes information into the context `c` to support later reasoning and acting.
  - Two regimes: **dense** thoughts for reason-heavy tasks (thought→action→obs every step) vs **sparse** thoughts for decision tasks with many actions (let the model choose when to think).
  - Base setup is a **frozen PaLM-540B** prompted with 1-6 hand-written thought/action/observation exemplars. No training required.

## 1. Method

<!-- "Dataset" would be wrong: ReAct introduces none. §1 describes the idea and the loop. -->

### The ReAct loop

- At step t the agent sees observation `o_t` and takes `â_t` under a policy `π(â_t | c_t)`, with context `c_t = (o_1, a_1, …, o_{t-1}, a_{t-1}, o_t)`. The twist: `â_t` may be a real action **or** a thought.
- Observed thought types: decompose the goal, inject commonsense, extract key facts from an observation, track progress / transition plans, handle exceptions and re-plan.

### Why the authors argue it's attractive

- **Intuitive to design** - annotators just write their thoughts on top of the actions they take; no ad-hoc format or thought-engineering.
- **General & flexible** - one recipe spans QA, fact-checking, text games, and web navigation despite very different action spaces.
- **Human-aligned & controllable** - traces are interpretable, and a human can **edit a thought mid-trajectory** to correct the agent on the fly.

### Action spaces are per-domain (not a benchmark they built)

- For knowledge tasks, a deliberately minimal **Wikipedia API** - verbatim:

  > `search[entity]` (returns the first 5 sentences of the entity's page, or top-5 similar entities), `lookup[string]` (returns the next sentence containing `string`, like Ctrl+F), `finish[answer]`.

- It's intentionally weaker than real lexical/neural retrievers - the point is to **force retrieval-by-reasoning**, mimicking how a human pokes at Wikipedia.

## 2. Experiments

<!-- Run on OTHERS' benchmarks - ReAct contributes the method, not the data. -->

### Setup

- Four existing benchmarks: **HotpotQA** (multi-hop QA), **FEVER** (fact verification), **ALFWorld** (text game), **WebShop** (web navigation). Question-only setup for the first two (no gold passages).
- Baselines are built by **ablating ReAct traces**: Standard (strip thoughts+actions+obs), CoT (reason-only), CoT-SC (self-consistency, 21 samples, majority vote), Act (strip thoughts).
- Two hybrids: **ReAct→CoT-SC** (fall back to CoT-SC if ReAct doesn't finish in N steps; N=7 HotpotQA / 5 FEVER) and **CoT-SC→ReAct** (fall back to ReAct when the CoT-SC majority is weak, < n/2).
- **Finetuning**: bootstrap 3,000 ReAct-generated correct trajectories to finetune PaLM-8B/62B.

## 3. Results

[Table 1: PaLM-540B prompting on HotpotQA (EM) and FEVER (Acc) - all methods]

- Knowledge tasks (PaLM-540B): the hybrids win - **ReAct→CoT-SC 35.1 EM** on HotpotQA and **CoT-SC→ReAct 64.6 Acc** on FEVER, both beating plain CoT (29.4 / 56.3) and CoT-SC (33.4 / 60.4). All prompting still far below supervised SoTA (67.5 / 89.5).
- Decision tasks: ReAct beats Act and the IL/RL baselines - ALFWorld **71%** (best-of-6) vs Act 45% vs BUTLER 37%; WebShop success rate **40.0%** vs Act 30.1% vs IL+RL 28.7% (expert human 59.6%).
- Key findings:
  1. **ReAct > Act everywhere** - reasoning guides acting, especially synthesizing the final answer.
  1. **ReAct vs CoT is a grounding/flexibility trade-off**: ReAct hallucinates far less (6% vs 14% false positives; hallucination is 56% of CoT's failures) but is **less flexible** (47% reasoning-error rate, including getting stuck repeating the same thought/action). This is exactly what motivates the hybrids - which are best overall.
  1. On decision tasks, **1-2-shot ReAct beats imitation/RL trained on 10³-10⁵ instances** (+34% ALFWorld, +10% WebShop, absolute success rate).
  1. **Finetuning flips the ranking**: prompted ReAct is the *worst* of four at small scale, but finetuned on just 3k traces it's the *best* - finetuned PaLM-8B ReAct beats all 62B prompting, and 62B beats all 540B prompting.

[Table 2: ReAct vs CoT success/failure-mode breakdown on HotpotQA]

## 4. Limitations

- The prompting setup caps how much reasoning+acting behavior fits - complex, large-action tasks need many demonstrations that blow past the in-context length limit.
- A ReAct-specific failure: repetitive thought/action loops where the model can't "jump out" (suspected greedy-decoding artifact).
- Brittle to retrieval quality - non-informative search derails reasoning and accounts for 23% of error cases.
- Still well below supervised/expert SoTA on every domain; the authors point to more finetuning data + RL as the path forward.
