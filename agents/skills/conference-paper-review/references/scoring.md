# Scoring principles (venue-neutral)

These principles apply to **every** venue. They tell you *how* to turn a paper into a judgment. The exact axes, scales, and labels you score on are **venue-specific** and live in the conference pack under `conferences/` (e.g. NeurIPS's 1 to 4 dimensions and 1 to 6 overall, or ARR's 1 to 5 Soundness/Excitement/Overall with half-points). Read the pack for the scale; read this for the reasoning behind the number.

The whole review hangs on **one relationship: does the evidence presented actually support the central claim, under the standard appropriate to the paper's type/track at this venue?** "High standard" means *rigorous and stingy with top marks*, **not** reflexively harsh: a sound contribution is not sunk by fixable or cosmetic problems, and an exciting framing does not rescue a claim the evidence cannot reach.

## First, classify every problem you find

Before scoring, sort the weaknesses into three bins. This sorting *is* the backbone of your judgment, and it stays **private**: it decides the scores and which field each issue lands in, but the bin labels themselves never appear anywhere in the review text.

- **Fatal (fundamental).** The central claim is not supported by the evidence as the standard for this type/track requires, **and the gap cannot be closed by a revision** - e.g. the headline effect is confounded with extra data/parameters/compute/tuning so it cannot be attributed to the proposed idea; the comparison is against a crippled or untuned baseline so the "improvement" is an artifact; the claimed generality rests on a single setting; for theory, the theorem doesn't follow from the assumptions or is weaker than the prose claims. Fatal flaws drive the score down.
- **Fixable.** A real gap that a revision could plausibly close - a missing baseline that could be added, an absent seed/variance report, an ablation that would isolate the effect, an under-specified detail needed for reproduction. Raise these clearly and name what would resolve them, but **a single fixable gap should not by itself sink an otherwise sound contribution.**
- **Cosmetic / non-decisive.** Typos, notation, phrasing, formatting, a mislabeled axis. These belong in the venue's "minor comments" field (NeurIPS: a fenced block in Strengths/Weaknesses; ARR: the "Comments, Suggestions, and Typos" field) and **must not** move any score.

The two cardinal errors, in opposite directions: letting a cosmetic/fixable issue masquerade as fatal (unfair harshness), or waving through a fatal claim-to-evidence gap because the writing is polished and the idea is appealing (unfair leniency). Decide the bin for the issues that actually determine the outcome, and keep the label to yourself; only the scores and the placement of each issue reflect it.

## What the score is anchored to

Whatever the scale, the accept/reject-facing number follows the same logic:

- **Central claim survives** scrutiny under the right standard, with only fixable/cosmetic issues remaining → the **acceptance** end of the venue's scale.
- **A fatal claim-to-evidence gap stands** → the **rejection** end of the venue's scale.
- Venues with a middle tier (e.g. ARR's Findings, a borderline band) catch the case where the work is *sound but modest in impact/novelty*: solid enough to be correct and useful, not strong enough for the top tier. Soundness gates correctness; impact/novelty moves the paper up from there.

State, in two or three sentences, which case the paper is in and why. Use any borderline or half-point options sparingly, as most forms request. Reserve the very top option (award, strong accept, "flawless and groundbreaking") for work that truly clears that bar.

## Significance/impact vs. rigor

Weigh significance and rigor above surface novelty. A careful, rigorous paper with modest novelty can outrank a flashy, under-supported one. Where a venue separates the axes (ARR splits objective **Soundness** from subjective **Excitement**), route rigor and claim-to-evidence support into the soundness-type axis and impact/innovation into the excitement/significance-type axis; do not let excitement compensate for a soundness failure on the acceptance decision. Remember that originality/contribution can be a new *evaluation*, a new *framing*, or a demonstrated efficiency/fairness gain, not only a new method.

## Confidence (1 to 5) - be honest

Most venues use the same 1 to 5 confidence scale; calibrate to what you actually did, not to how decisive you'd like to sound.

- Default to **3** for one careful reading where you did not exhaustively verify proofs or survey all related work ("fairly confident; math/other details not carefully checked" is literally true of most reads).
- **4** if you know the subarea well and checked the key arguments/derivations carefully.
- **2** if the paper is largely outside your competence or you suspect you missed central parts.
- **5** only if you verified the math and related work meticulously - **rare**; do not reach for it by default.
- **1** for an educated guess on an out-of-area or hard-to-parse paper.

Overclaiming confidence is a real failure mode for automated review. When in doubt, 3.

## Make the concerns actionable

Whatever field invites concerns or questions (NeurIPS "Questions"; ARR "Summary of Weaknesses", ideally numbered so authors can respond point by point), write concerns whose answers could *change your judgment*, and know privately how. **Never write the score consequence into the review**: no "my soundness score would rise from 2 to 3", no "this caps my score", and no severity labels next to items. The useful pattern is a concrete, self-contained request that states what would resolve the concern:

> "Please add baseline B under the same compute/tuning budget and report variance across ≥3 seeds. If the gain persists at ≥X, the confound is ruled out; if it disappears, the headline claim needs restating."

Prefer concerns that isolate the proposed effect (an ablation that removes the extra data/parameters; a control that equalizes compute; a seed/variance report; the single missing baseline). Authors may lack large compute on a short timeline, so ask for the *cheapest experiment that would resolve the question*, and say what question it resolves. Avoid laundry lists; pick the few cruxes. Aim for 3 to 5 substantive items. When rebuttal answers arrive, re-run the private sort and move the scores accordingly; the movement lives in the scores, not in the prose.

## Limitations and candor

If the authors have honestly stated their limitations and any negative societal impact, that is a complete and creditable answer. **Reward candor - do not punish a paper for naming its own weaknesses.** If something load-bearing is unacknowledged (a confound, a scope limit, a foreseeable misuse or dual-use risk), name it constructively as the gap to add, in the venue's limitations field.

Where the venue's limitations field accepts a bare **"yes"** (e.g. NeurIPS), answer "yes" **only** when the paper contains an explicit limitations section (a dedicated section discussing the work's limitations). If the paper has no such section, do **not** answer "yes": instead give a fuller, more verbose response that names the load-bearing limitations the authors should have acknowledged and explains how adding them would strengthen the work.
