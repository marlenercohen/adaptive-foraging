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
