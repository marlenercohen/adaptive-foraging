# Adding a New Stimulus Set

This guide is for lab members preparing a new stimulus set for experiments.

## Conceptual overview

A stimulus set is three things that belong together:

1. A manifest file that describes the set.
2. A metadata table that describes each stimulus item.
3. A folder of stimulus images (if images are used).

Think of it this way:

- The manifest answers: "What is this set, and what features does it define?"
- The metadata answers: "What are the individual stimuli, and what are their feature values?"
- The images answer: "What visual items are shown to participants?"

All three must stay aligned.

## Version stability

Once a stimulus set has been used to collect experimental data, treat it as immutable.

- Do not modify stimuli, feature schema, or metadata in place for an already-used set.
- If changes are needed, create a new version of the stimulus set instead.

This protects reproducibility: past datasets must remain interpretable against the exact stimulus definition used during collection.

## Required folder structure

Create one folder per stimulus set under [stimuli](stimuli), for example:

- stimuli/faces/manifest.json
- stimuli/faces/metadata.json
- stimuli/faces/images/...

Current example set:

- [stimuli/emoji/manifest.json](stimuli/emoji/manifest.json)
- [stimuli/emoji/metadata.json](stimuli/emoji/metadata.json)

## Required files and their purpose

### Manifest file (manifest.json)

Purpose:
Defines the stimulus set itself (identity, feature schema, and file references).

Required fields:

- name
- displayName
- description
- version
- imageDirectory
- metadataFile
- features

### Metadata file (metadata.json)

Purpose:
Lists each stimulus item and its feature values.

Format:

- One object per stimulus item.
- Required fields per item:
  - id
  - display
  - features

### Images folder (images/)

Purpose:
Stores stimulus image files for the set (if the set uses image files).

Notes:

- Keep image files for a set inside that set’s folder structure.
- Ensure metadata and manifest references are consistent with your folder layout.

## Feature schema format

The feature schema is defined in manifest.json under features.

Why this schema exists:

- It documents stimulus features clearly for scientists.
- It allows the software to validate stimulus sets, rules, and protocols automatically.

Each feature definition includes:

- name
- displayName
- type

Supported types:

- boolean
- categorical
- continuous

Type requirements:

- boolean: true/false style feature
- categorical: must include allowed values
- continuous: may include units

Examples of feature definitions:

- Boolean example:
  - name: animal
  - displayName: Animal
  - type: boolean

- Categorical example:
  - name: emotion
  - displayName: Emotion
  - type: categorical
  - values: happy, sad, angry, neutral

- Continuous example:
  - name: orientation
  - displayName: Orientation
  - type: continuous
  - units: degrees (optional)

Validation expectations:

- Every feature name must be unique.
- Every feature must use a supported type.
- Categorical features must define allowed values.
- Continuous features may define units.

## Metadata format requirements

Each row in metadata.json represents one stimulus.

Required row fields:

- id: unique identifier
- display: participant-facing label/symbol/name for that stimulus
- features: key-value map for feature values

Feature alignment rule:

- Feature keys in metadata must match feature names defined in the manifest schema.
- Values should match the declared feature type.

## Rules and feature names (scientist-facing summary)

Rules are built using feature names from the stimulus set’s feature schema.

Practical implication:

- If a rule references a feature, that feature must exist in the selected stimulus set schema.
- Keep rule logic and feature schema aligned when designing protocols.

## Worked example: current Emoji set

Reference files:

- [stimuli/emoji/manifest.json](stimuli/emoji/manifest.json)
- [stimuli/emoji/metadata.json](stimuli/emoji/metadata.json)

What this example shows:

- A complete manifest with feature schema.
- A metadata table where each row contains id, display, and features.
- A consistent feature vocabulary across the set.

Recommendation:

- Treat the Emoji set as the reference implementation.
- For a new stimulus set, start by copying the Emoji set folder and then modify:
  - manifest metadata
  - feature schema
  - metadata rows
  - image assets

## Common mistakes

- Feature name mismatch:
  - Manifest uses one name, metadata uses a different name.
- Duplicate feature names in manifest.
- Missing required manifest fields.
- Missing required metadata row fields (id, display, features).
- Categorical feature without allowed values.
- Categorical metadata value not in allowed values.
- Inconsistent value conventions across stimuli (for example mixing incompatible boolean encodings).
- Incorrect file paths in manifest for metadata or images.
- Reusing ids across multiple stimuli.

## Testing a new stimulus set before data collection

1. Structure check:
   - Confirm folder contains manifest, metadata, and image assets (if used).
2. Manifest check:
   - Confirm all required fields are present.
   - Confirm feature schema is complete and valid.
3. Metadata check:
   - Confirm each row has id, display, features.
   - Confirm metadata feature keys and value types match schema.
4. Protocol check:
   - Point one test block to the new stimulus set name.
5. Experimental sanity check:
   - Verify expected experimental behavior, not just display.
   - Confirm that stimuli expected to satisfy a rule are rewarded.
   - Confirm that stimuli expected not to satisfy a rule are not rewarded.
6. Rule alignment check:
   - Verify experimental rules rely only on features in this set.
7. Small pilot run:
   - Complete a short trial and review outputs for expected behavior.
8. Freeze for collection:
   - Record the set version and avoid changing files mid-study.

## Quick checklist for adding a stimulus set

1. Create a new set folder under [stimuli](stimuli).
2. Add manifest.json with required fields.
3. Add metadata.json with one object per stimulus.
4. Add image assets (if applicable).
5. Verify feature schema and metadata alignment.
6. Confirm rule-feature compatibility.
7. Run a short pilot test.
8. Version-lock before collecting real data.

## Design Principle

A stimulus set should completely describe the stimuli used in an experiment without requiring changes to the experiment engine.

If adding a new stimulus set requires modifying JavaScript code, the architecture should be reconsidered.
