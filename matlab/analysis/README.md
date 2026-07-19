# Analysis Layer Architecture

This directory implements the first two model-agnostic layers for behavioral analysis.

## Layer 1: Facts (immutable)

- Function: `af.buildCanonicalState`
- Responsibility: store reconstructed trial facts and optional stimulus/rule metadata without adding theory-dependent quantities.
- Immutable fact tables:
	- `trials`
	- `stimuli`
	- `rules`
	- `boardState` when JSON `session.stateSnapshots` are provided

`boardState` is a Layer-1 fact table derived directly from the experiment
logger's recorded board snapshots. It represents the objective board
configuration before each human decision and should be used by future
analyses that need available-stimulus sets or rule-matching opportunity
counts, rather than storing redundant availability summaries in Layer 2.

## Layer 2: State (deterministic pre-decision reconstruction)

- Function: `af.reconstructDecisionState`
- Responsibility: compute what is objectively true immediately before each human decision.
- Excludes model-dependent fields (beliefs, evidence, uncertainty, flexibility, latent values).

## Pipeline entry point

- Function: `af.buildDecisionState`
- Responsibility: run `trials -> canonical facts -> decision state`.

## Layer 3 descriptive modules

- `af.computeStimulusDifficulty`: per-stimulus descriptive interaction summaries.
- `af.summarizeRuleBehavior`: descriptive behavior summaries grouped by rule.
- `af.evaluateRuleConsistency`: objective long-format `decision x candidate rule`
	evaluations used by future flexibility/switching/model analyses.
- `af.buildRuleObservationHistory`: objective cumulative observation-history
	context per `decision x candidate rule`.
- `af.reconstructAvailableBoard`: canonical objective board availability
	reconstruction before each human decision.

## Notes

- The output is intentionally minimal and extensible.
- Future analysis/model code should consume `decisionState` and keep theory-specific variables in separate Layer 3 modules.
