# Adaptive Foraging v0.001

Open index.html in a browser.

This version establishes the project structure and a working World object.
Next versions will add the board, rules, logging and agents.

## Adding a stimulus set

Stimulus sets are discovered from `stimuli/index.json`. The browser runtime does not scan directories automatically.

To add a new stimulus set:

1. Create a new folder under `stimuli/`.
2. Export `manifest.json` and `metadata.json` into that folder.
3. Add one entry to `stimuli/index.json` that points to the set's `manifest.json`.

Example entry:

```json
{
	"myset": {
		"manifestFile": "stimuli/myset/manifest.json"
	}
}
```

## Protocol Loops

The protocol language supports an optional top-level `loops` array for repeating contiguous groups of phases without duplicating phase definitions.

Example:

```json
{
	"name": "Example protocol",
	"phases": [
		{ "name": "Intro", "episodeCount": 2 },
		{ "name": "A", "episodeCount": 1 },
		{ "name": "B", "episodeCount": 1 },
		{ "name": "C", "episodeCount": 1 },
		{ "name": "Outro", "episodeCount": 2 }
	],
	"loops": [
		{
			"name": "Training block",
			"startPhase": 1,
			"endPhase": 3,
			"repeatCount": 4
		}
	]
}
```

Semantics:

1. `startPhase` and `endPhase` are zero-based phase indices, inclusive.
2. `repeatCount` is the number of additional repetitions after the first execution.
3. In the example above, phases `1..3` execute 5 total times (`1 + repeatCount`), then execution continues at phase `4`.

Validation rules for the initial loop implementation:

1. Loops must be non-overlapping.
2. Loops must be non-nested.
3. Loops must be listed in ascending order of `startPhase`.
4. Violations produce a descriptive protocol error.

Compatibility notes:

1. Protocols without `loops` work unchanged.
2. The legacy `repeat` / `repeatFromPhase` mechanism is still supported when `loops` is not present.
3. `loops` cannot be combined with legacy repeat fields in the same protocol.
