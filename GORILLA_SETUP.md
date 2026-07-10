# Gorilla setup for Adaptive Foraging

The hosted task sends one Gorilla metric object after the complete session JSON has been stored successfully, then sends `finished` so Gorilla advances.

In the cloned Gorilla iFrame task, add these metric definitions using the exact keys below:

- `session_id` (Text)
- `upload_succeeded` (Boolean)
- `upload_object_key` (Text)
- `upload_bytes` (Number)
- `completed_episodes` (Number)
- `human_total_score` (Number)
- `agent_total_score` (Number)
- `completion_reason` (Text)
- `upload_error` (Text)

Keep the iFrame task's `url` manipulation set to:

`https://marlenercohen.github.io/adaptive-foraging/`

For Prolific recruitment, configure Gorilla's recruitment policy as Prolific. Prolific identity remains in Gorilla's participant export. The shared `session_id` metric joins each Gorilla row to the JSON object stored in R2.
