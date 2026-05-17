## Wiki Routing

This repository has a standalone project wiki workflow at `.agents/workflows/wiki.md`.
Use it when the user asks to remember, record, look up, summarize, or maintain
project knowledge that should persist in the repository.

Route wiki requests as follows:

- Lookup or "what do we know about X": run `.\.agents\workflows\wiki.ps1 wiki_query -InputJson '{"query":"X"}' -Json`.
- Read a known page: run `.\.agents\workflows\wiki.ps1 wiki_read -InputJson '{"page":"page-slug"}' -Json`.
- List existing knowledge: run `.\.agents\workflows\wiki.ps1 wiki_list -Json`.
- Add or update knowledge: run `.\.agents\workflows\wiki.ps1 wiki_add -InputJson '{"title":"Title","content":"...","tags":["tag"],"category":"decision"}' -Json`.
- Ingest structured project notes: run `.\.agents\workflows\wiki.ps1 wiki_ingest -InputJson '{"title":"Title","content":"...","tags":["tag"],"category":"reference"}' -Json`.
- Validate wiki health after edits: run `.\.agents\workflows\wiki.ps1 wiki_lint -Json`.

Wiki content is stored under `.wiki/`:

- Pages: `.wiki/*.md`
- Index: `.wiki/index.md`
- Log: `.wiki/log.md`

Use these categories when adding pages:
`architecture`, `decision`, `pattern`, `debugging`, `environment`,
`session-log`, `reference`, `convention`.

Constraints:

- Query is keyword and tag based only; do not assume embeddings or semantic search.
- Prefer the PowerShell entry point on Windows. Use `.agents/workflows/wiki.sh` only
  from sh/bash environments.
- Session capture is explicit. If a session summary should persist, add it with
  category `session-log`; there is no background auto-capture service.
