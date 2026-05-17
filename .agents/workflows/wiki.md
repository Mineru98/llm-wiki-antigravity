---
description: Persistent markdown project wiki stored under repository .wiki with keyword search and lifecycle capture
---

# Wiki

Persistent, self-maintained markdown knowledge base for project and session knowledge.

This project uses a standalone wiki implementation. Run commands from the repository root with `.\.agents\workflows\wiki.ps1` on PowerShell or `./.agents/workflows/wiki.sh` on sh/bash.

## Operations

### Ingest
```powershell
.\.agents\workflows\wiki.ps1 wiki_ingest -InputJson '{"title":"Auth Architecture","content":"...","tags":["auth","architecture"],"category":"architecture"}' -Json
```
```sh
./.agents/workflows/wiki.sh wiki_ingest --input '{"title":"Auth Architecture","content":"...","tags":["auth","architecture"],"category":"architecture"}' --json
```

### Query
```powershell
.\.agents\workflows\wiki.ps1 wiki_query -InputJson '{"query":"authentication","tags":["auth"],"category":"architecture"}' -Json
```
```sh
./.agents/workflows/wiki.sh wiki_query --input '{"query":"authentication","tags":["auth"],"category":"architecture"}' --json
```

### Lint
```powershell
.\.agents\workflows\wiki.ps1 wiki_lint -Json
```
```sh
./.agents/workflows/wiki.sh wiki_lint --json
```

### Quick Add
```powershell
.\.agents\workflows\wiki.ps1 wiki_add -InputJson '{"title":"Page Title","content":"...","tags":["tag1"],"category":"decision"}' -Json
```
```sh
./.agents/workflows/wiki.sh wiki_add --input '{"title":"Page Title","content":"...","tags":["tag1"],"category":"decision"}' --json
```

### List / Read / Delete
```powershell
.\.agents\workflows\wiki.ps1 wiki_list -Json
.\.agents\workflows\wiki.ps1 wiki_read -InputJson '{"page":"auth-architecture"}' -Json
.\.agents\workflows\wiki.ps1 wiki_delete -InputJson '{"page":"outdated-page"}' -Json
.\.agents\workflows\wiki.ps1 wiki_refresh -Json
```
```sh
./.agents/workflows/wiki.sh wiki_list --json
./.agents/workflows/wiki.sh wiki_read --input '{"page":"auth-architecture"}' --json
./.agents/workflows/wiki.sh wiki_delete --input '{"page":"outdated-page"}' --json
./.agents/workflows/wiki.sh wiki_refresh --json
```

## Categories
`architecture`, `decision`, `pattern`, `debugging`, `environment`, `session-log`, `reference`, `convention`

## Storage
- Pages: `.wiki/*.md`
- Index: `.wiki/index.md`
- Log: `.wiki/log.md`

## Cross-References
Use `[[page-name]]` wiki-link syntax to create cross-references between pages.

## Auto-Capture
Session-end auto-capture remains a workflow convention, not a background service. Add session logs explicitly with `wiki_add` or `wiki_ingest` using category `session-log`.

## Hard Constraints
- No vector embeddings; query uses keyword + tag matching only.
- The sh/bash entry point uses standard shell tools only: `sh`, `awk`, `sed`, `grep`, `find`, `sort`, `date`, `mkdir`, and `rm`.
- Wiki files are repository project knowledge under `.wiki/`.
