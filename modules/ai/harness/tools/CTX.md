# CTX

Use ctx to search prior local coding-agent sessions before you answer or edit.

Run:
ctx search "<focused query>"

Search multiple terms:
ctx search --term "<term one>" --term "<term two>"

Inspect the best result:
ctx show event <ctx-event-id> --window 3
or:
ctx show session <ctx-session-id>

If retrieved history affects your answer, cite the ctx_event_id or
ctx_session_id and include the ctx command you ran.