# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PageIndex RAG v2 — vectorless, reasoning-based document Q&A with workspace isolation and per-user auth. Flask backend + vanilla JS SPA. Supports Claude (via LiteLLM proxy) or Ollama.

See also: [README.md](README.md) (user-facing), [SECURITY.md](SECURITY.md) (threat model).

---

## Prerequisites

- Python 3.12+
- [uv](https://docs.astral.sh/uv/) — fast Python package manager (replaces pip)
- Git
- Linux (Ubuntu 22.04+ recommended)
- Claude API key **or** Ollama installed locally

---

## Setup (uv — recommended)

### 1. Install uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env   # or restart terminal
uv --version                  # verify
```

### 2. Clone this repo

```bash
git clone https://github.com/Harinath-Rajendran/pageindex-rag.git
cd pageindex-rag
```

### 3. Clone and set up PageIndex (external dependency)

PageIndex is the vectorless tree-index builder used for PDF section navigation.

```bash
# Clone into /PageIndex (default location the app expects)
git clone https://github.com/VectifyAI/PageIndex.git /PageIndex
cd /PageIndex

# Create its own venv and install
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate

cd -   # back to pageindex-rag
```

> **Note:** PageIndex is optional. If `/PageIndex` doesn't exist, the app falls back gracefully to full-text extraction for PDFs — all other formats (DOCX, XLSX, TXT, CSV) are unaffected.

### 4. Create project venv and install dependencies

```bash
# From inside pageindex-rag/
uv venv venv --python 3.12
source venv/bin/activate

# Install all dependencies
uv pip install -r requirements.txt
```

### 5. Configure environment

```bash
cp .env.example .env
nano .env    # fill in your ANTHROPIC_API_KEY or Ollama config
```

---

## Commands

### Development

```bash
# Terminal 1 — LiteLLM proxy (Claude only, skip if using Ollama)
source venv/bin/activate
litellm --config litellm_config.yaml --port 4000

# Terminal 2 — Flask app
source venv/bin/activate
export $(grep -v '^#' .env | xargs)
python app.py    # http://localhost:5000
```

### Production (systemd)

```bash
sudo bash setup.sh           # installs systemd services

sudo systemctl start litellm-proxy    # Claude only
sudo systemctl start pageindex-rag

# Logs
journalctl -fu pageindex-rag
journalctl -fu litellm-proxy
```

### Add / update a dependency

```bash
source venv/bin/activate
uv pip install <package>
uv pip freeze > requirements.txt   # update lockfile
```

### API smoke tests (with auth)

```bash
# Login
curl -c cookies.txt -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}'

# List groups
curl -b cookies.txt http://localhost:5000/api/groups

# Upload a file
curl -b cookies.txt -X POST http://localhost:5000/api/upload \
  -H "X-Group: hr" \
  -F "file=@/path/to/document.pdf"

# Query
curl -b cookies.txt -X POST http://localhost:5000/api/query \
  -H "Content-Type: application/json" -H "X-Group: hr" \
  -d '{"question":"What is the AMC cost?"}'

# Health
curl http://localhost:5000/health
```

---

## Architecture

**Entry point:** `app.py` (~1000 lines) — Flask routes + auth + text extraction + router + retrieval + synthesis.  
**Frontend:** `static/index.html` — single-file vanilla JS SPA, no build step. Black/orange theme.

### Key Environment Variables (`.env`)

| Variable | Default | Purpose |
|---|---|---|
| `LLM_MODE` | `claude` | `claude` or `ollama` |
| `ANTHROPIC_API_KEY` | — | Required for Claude backend |
| `LITELLM_BASE_URL` | `http://localhost:4000` | LiteLLM proxy endpoint |
| `LITELLM_API_KEY` | `sk-placeholder` | LiteLLM auth token (change in prod) |
| `QUERY_MODEL` | `claude-sonnet` | Model for Q&A synthesis |
| `INDEX_MODEL` | `claude-sonnet` | Model for PDF tree building |
| `PAGEINDEX_DIR` | `/PageIndex` | Path to PageIndex repo |
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Ollama server URL |
| `OLLAMA_MODEL` | `gemma3:4b` | Ollama model name |
| `COOKIE_SECURE` | `0` | Set `1` behind HTTPS |
| `CORS_ORIGINS` | `` | Comma-separated origins; blank = same-origin only |
| `PORT` | `5000` | Flask listen port |

### File-Based State

```
state/
  groups.json          — workspace config (auto-seeded: hr, it, developers)
  users.json           — user records {username, password_hash, groups, is_admin}
  .secret_key          — Flask session signing key (persistent)
  doc_{id}.json        — document metadata + group + summary
  job_{id}.json        — indexing job status (queued → indexing → ready/error)

uploads/{doc_id}.{ext} — raw uploaded files
texts/{doc_id}.txt     — extracted text cache (auto-generated)
indexes/{job_id}.json  — PageIndex trees (PDF only, optional)
```

### Auth & Authorization

- **flask-login** sessions with HttpOnly + SameSite=Lax cookies.
- `@api_login_required` on every `/api/*` endpoint — rejects unauthenticated with 401.
- Every endpoint verifies `doc.group` is in `current_user.groups` (admins bypass).
- Login rate limit: 8 failed attempts / 5 min / IP → 429.
- Default seeded user: `admin` / `admin` — **change immediately**.

### Query Flow (vectorless, auto-routed)

```
1. resolve_group(request)            → active workspace
2. extract_query_tokens(question)    → IPs / dates / IDs / quoted phrases
3. route_docs()                      → 1 LLM call over {filename, summary} manifest → top-K docs
4. parallel retrieve_from_doc()      via ThreadPoolExecutor:
     PDF with tree  → tree-nav LLM call → focused page extraction
     XLSX/XLS/CSV   → filter_excel_by_tokens() → matching rows + context
     Other          → cached text up to format cap
5. synthesis LLM call                → labeled sources, strict cite instructions
6. return {answer, routed_docs, sources, model, group}
```

### Per-Format Caps

| Format | `get_doc_text` cap | Per-doc synthesis cap |
|---|---|---|
| pdf | 40K chars | 15K (post tree-nav) |
| docx | 60K chars | 20K |
| txt / md | 60K chars | 20K |
| csv | 150K chars | 50K |
| xls / xlsx | 200K chars | 80K (post token filter) |

XLSX gets the biggest caps — tables are dense and truncation causes silently wrong answers.

### Background Processing

Upload spawns `threading.Thread(target=run_pageindex)`.  
Flow: **extract text → cache → generate_doc_summary() → optional PageIndex tree (PDF only)**.  
Frontend polls `/api/jobs/{id}` every 3 s. `STATE_LOCK` guards all file writes.

### PageIndex Tree Builder (PDF Only, Optional)

External subprocess at `$PAGEINDEX_DIR/run_pageindex.py`. Skipped if dir doesn't exist — app degrades gracefully to full-text extraction.

---

## Frontend Structure

- Login gate covers the app; session restored via `/api/auth/me` on load.
- **Header:** logo · workspace switcher · LLM badge · status dot · user chip · Admin button · Sign out.
- **Sidebar:** upload zone (routes to active workspace) · doc list (filtered by workspace) · delete-on-hover.
- **Main:** auto-routed chat · "Routed to N docs" banner · grouped citations.
- **Admin modal:** Users tab (create / edit / delete / toggle admin / assign workspaces) + Workspaces tab.
- All fetches send `credentials: 'include'`. 401 responses auto-redirect to login.

---

## Known Gotchas

- **LiteLLM model names** must be `openai/claude-sonnet` format in `litellm_config.yaml`, not bare `claude-sonnet`.
- **Scanned PDFs** with no extractable text fail with "OCR not yet supported".
- **Multi-worker gunicorn** will race on JSON state files. Use `--workers 1 --threads N`.
- **HTTPS required** for `COOKIE_SECURE=1` — otherwise sessions silently fail to persist.
- **Default admin/admin** exists after first boot — logged as WARNING. Change before any real deployment.
- **PageIndex subprocess** is blocking; keep timeouts generous for large PDFs.
- **uv not in PATH** after install: run `source $HOME/.local/bin/env` or add `$HOME/.local/bin` to `~/.bashrc`.
