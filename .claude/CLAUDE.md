# Token-saving rules (strict)

1. Never read a whole file over 150 lines. Use a line range (offset/limit, `sed -n 'a,bp'`) or grep for the part you need.
2. Pipe test and terminal command output through `head -n 25` to keep logs short.
3. No conversational chatter. Give direct, concise code diffs and short status lines.
4. Do not re-read a file already inspected in this chat unless it has been modified since.

These rules apply to agents launched from this project too: put them in every agent prompt.

## Agents (owner's choice)

- Launch agents on the cheaper model by default (`model: "sonnet"`). Use the stronger model only for a hard job (for example
  the part-kit ants renderer), and say why when doing it.
- Run about 2–3 agents at a time, not 7.
