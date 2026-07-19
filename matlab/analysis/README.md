# Analysis Layer Architecture

This directory implements the first two model-agnostic layers for behavioral analysis.

## Layer 1: Facts (immutable)

- Function: `af.buildCanonicalState`
- Responsibility: store reconstructed trial facts and optional stimulus/rule metadata without adding theory-dependent quantities.

## Layer 2: State (deterministic pre-decision reconstruction)

- Function: `af.reconstructDecisionState`
- Responsibility: compute what is objectively true immediately before each human decision.
- Excludes model-dependent fields (beliefs, evidence, uncertainty, flexibility, latent values).

## Pipeline entry point

- Function: `af.buildDecisionState`
- Responsibility: run `trials -> canonical facts -> decision state`.

## Notes

- The output is intentionally minimal and extensible.
- Future analysis/model code should consume `decisionState` and keep theory-specific variables in separate Layer 3 modules.
