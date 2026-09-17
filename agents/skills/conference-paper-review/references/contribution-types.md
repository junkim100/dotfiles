# NeurIPS 2026 Contribution Types - rubrics and how they shift the bar

> **Venue-specific (NeurIPS).** Contribution Types are a NeurIPS construct. Load this only when the target venue is NeurIPS; the NeurIPS pack (`conferences/neurips-2026.md`) points here. Other venues (e.g. ARR/ACL) use different axes defined in their own pack.

Authors select **one** Contribution Type at submission; it **cannot** be changed by authors or reviewers afterward. The review form is identical across types, but **Quality / Clarity / Significance / Originality mean different things per type**, and **you must assess the paper under the type the authors selected** - not the type you wish they had chosen. If the authors' selected type is not visible to you (it usually isn't in the PDF), infer the most likely type from the paper's primary contribution, state which type you assessed under, and note that the score is conditional on that type. The authoritative current text lives at `https://neurips.cc/Conferences/2026/ReviewerGuidelines` - fetch it if you have network access and reconcile any drift with the snapshot below.

The single most important consequence for this skill: **the evidentiary standard the central claim must meet depends on the type.** Demanding many seeds and SOTA baselines is correct for a General/Use-Inspired empirical claim and *wrong* for a Theory paper. Match the evidence you require to what the authors set out to do.

______________________________________________________________________

## General (most submissions)

The default empirical/methods rubric. Apply the full claim-evidence machinery here: strong baselines under comparable tuning and compute, multiple seeds with reported variance, ablations and controls that rule out confounds (extra data, extra parameters, longer training, better-tuned hyperparameters on the proposed side only).

- **Quality** - Technically sound? Claims supported by theory/experiments? Methods appropriate? Complete work vs. work-in-progress? Are authors honest about strengths **and** weaknesses?
- **Clarity** - Clearly written and organized? A superbly written paper gives an expert enough to **reproduce** the results.
- **Significance** - Will others use or build on it? Does it address a hard task better than prior work? Does it demonstrably advance understanding, or provide unique data/conclusions/approach?
- **Originality** - New insights, deeper understanding, or important properties of existing methods? Clearly differentiated from prior work with citations? Note: originality does **not** require a brand-new method - novel evaluation of existing methods, or demonstrated efficiency/fairness gains, counts equally.

______________________________________________________________________

## Theory (main contribution is analysis + proofs)

**Do not impose the empirical bar here.** A theory paper that lacks experiments is not deficient for that reason.

- **Quality** - Mathematical **rigor and correctness** is the primary criterion. Proofs, lemmas, and the logical flow must be sound. You are not expected to verify every line, but examine the core arguments enough to be confident in the results. Assumptions are allowed; judge "good" assumptions against the novelty of the result and the norms of the literature.
  - **Empirical validation is not necessary.** New algorithms here need not beat SOTA. If experiments appear, their role is to illustrate the formal insight, not to compete on the largest datasets. **Do not penalize a theory paper for lacking experiments.**
- **Clarity** - Rigor **and** intuition: the high-level proof strategy / the intuition behind a new definition should be given before the technical details. The type of contribution must be signposted early; novel vs. prior work must be unambiguous.
- **Significance** - Look for impact via either: **novel abstractions/formulations** (a new rigorous framework or definition that gives the community vocabulary for a phenomenon), or **progress on established problems** (real progress, a new angle on a bottlenecked problem, or solving an open problem).
- **Originality** - Technical novelty: a new proof technique, a novel synthesis of tools from other fields, or a fundamentally new way to parameterize/define a problem.

For Theory, the "claim-evidence" link becomes **claim ↔ proof**: does the theorem as stated actually follow from the assumptions and the argument given, and is the theorem the one the prose claims? Confounds become **hidden assumptions** smuggled in mid-proof, **gaps** in the argument, and **overstated corollaries** that the theorem doesn't reach.

______________________________________________________________________

## Use-Inspired (framing/designing approaches for a real-world application)

- **Quality** - Is the use case **real and meaningful**, arising from the pre-existing needs of users **outside** the NeurIPS community (not artificially constructed to make an interesting ML problem)? Is the **design matched to the use case** (task framing, methods, metrics tied to real needs - e.g., physical constraints, interpretability, robustness)? **Expect non-standard datasets** - real-world data outside common ML benchmarks should be *encouraged* when justified by the use case, not penalized for being unusual.
- **Clarity** - Measured **relative to an ML audience**: domain motivation is fine, but the reader should not need domain expertise; jargon must be explained.
- **Significance** - Impact on an important use case **and/or** on the broader NeurIPS community; simple-to-apply ideas can be especially valuable. **Compare against commonly-used non-ML approaches** for that application, not only ML baselines.
- **Originality** - Need not be wholly novel methods; a novel combination matched to the data, or a novel framing driven by the application's needs, qualifies. The paper should give insight into **why** methodological choices work or fail in this context.

For Use-Inspired, a common reviewer error is to ding "weird" datasets or missing standard benchmarks. Resist it: the right question is whether the evaluation is faithful to the *use case*, and whether non-ML baselines that practitioners actually use were included.

______________________________________________________________________

## Concept & Feasibility (highly novel, high-reward idea, scope beyond one paper)

**Significance and originality bars are HIGH.**

- **Quality** - Still must be technically sound; claims **rigorously grounded** through some combination of empirical, analytical, and conceptual argument. The scope of the idea may exceed what a single paper can validate, but it must be **strongly supported nonetheless** (contrast: a workshop paper may be only partially supported - that is not acceptable here).
- **Clarity** - Same as General: clear, organized, reproducible-by-an-expert.
- **Significance** - **High potential to change approaches/understanding.** The promise must go well beyond the specific evaluations included; it should have potential to shift paradigms or practice substantively. Evaluations should be chosen to *signal* that broader significance.
- **Originality** - **Highly novel ideas** that change how problems or methods are approached.

For C&F, don't sink the paper because the idea isn't fully validated (that's expected) - but do hold the line that the *partial* evidence presented must be sound and must genuinely point toward the claimed broader significance. The failure mode is a grand claim with evidence that doesn't actually bear on it.

______________________________________________________________________

## Negative Results (main contribution is understanding a negative result)

**Significance and originality bars are HIGH.**

- **Quality** - Must be more than "an experiment didn't turn out as hoped." The negative result must be **grounded in deeper analysis** - conceptually-informed conjectures plus careful experimentation, rigorous proofs, or a combination.
- **Clarity** - Same as General.
- **Significance** - Must **change how the community addresses a question**, or expose that the community should be addressing an important question differently. A negative result about something few people need is **not** significant. (It need not provide a fix; future work can.)
- **Originality** - Must be **surprising or unexpected** - counter to a popularly held understanding. A negative result that readers already know or would be unsurprised by is rigorous and clear but **not original** (the guidelines' own example: "a linear classifier cannot separate a nonlinear boundary" - true, clean, important, but not original).

For Negative Results, the claim-evidence question is twofold: (1) is the negative finding *real* and not an artifact of a weak implementation, a bad baseline on the authors' side, or insufficient tuning/compute (a botched method is not a negative result); and (2) is it *surprising* and *consequential* enough to clear the high bar.

______________________________________________________________________

## Quick selector

Decide the type by asking **what is the paper's primary contribution?**

- A new method/model/architecture/recipe with empirical claims → **General**.
- A formal result; theorems and proofs are the point → **Theory**.
- Built to serve a concrete real-world application, motivated by outside-ML user needs → **Use-Inspired**.
- A bold idea whose full validation exceeds one paper, pitched at paradigm-shift scale → **Concept & Feasibility**.
- The finding is that something *doesn't* work / a believed thing is false → **Negative Results**.

When a paper blends types, pick the dominant one, state your choice, and assess under it. Borrow a sub-criterion from another type only if the paper genuinely spans both.
