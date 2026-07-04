# Adaptive Foraging MATLAB Analysis Package

This MATLAB package is independent of the JavaScript experiment runtime.

## Public functions

- `session = loadSession(filename)`
- `summary = summarizeSession(session)`
- `episodes = summarizeEpisodes(session)`

## Supported descriptive outputs

Whole-session summary includes:

- experiment metadata
- protocol metadata
- stimulus set(s)
- rules encountered
- reward structures encountered
- working memory parameters
- termination policy
- number of episodes
- number of rule switches
- participant score
- agent score
- total turns
- participant rewards
- agent rewards

Episode summary includes one row per episode:

- episode number
- block
- rule
- episode length
- participant score
- agent score
- participant rewards
- agent rewards

## Example

```matlab
session = loadSession('adaptive_foraging_2026-07-04_1542.json');
summary = summarizeSession(session);
episodes = summarizeEpisodes(session);
```
