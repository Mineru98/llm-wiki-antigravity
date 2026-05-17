Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

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
