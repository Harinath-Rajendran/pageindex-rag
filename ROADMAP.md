# Roadmap — Turning PageIndex RAG into a first-class AI chatbot

Ordered by effort → impact. Everything here is **additive** and keeps the vectorless design.

## 🚀 Ship soon (quick wins, days of work)

### 1. Stream LLM responses
Current: `/api/query` waits for the full answer then returns JSON.
Fix: switch to Server-Sent Events (SSE) and stream tokens to the chat bubble. Perceived latency drops ~3×. LiteLLM + OpenAI SDK both support `stream=True`.

### 2. Persistent chat history per user
Today each refresh wipes the conversation. Store chats in `state/chat_{user}_{uuid}.json`. Add a left-rail "Chats" section above "Documents" showing recent conversations.

### 3. Markdown + code rendering
Current renderer only handles `**bold**`. Add [`marked.js`](https://github.com/markedjs/marked) (+ `highlight.js` for code). Bots look dramatically more professional instantly.

### 4. Copy / regenerate / edit buttons on messages
Tiny icons on hover. Regenerate re-sends the previous user message. Edit lets the user fix a question without retyping.

### 5. Suggested follow-up questions
After each answer, a cheap LLM call returns 3 next-question chips. Huge UX win — turns the bot into something people can explore with.

### 6. Keyboard shortcuts
- `/` focus input
- `Cmd/Ctrl+K` open command palette (search docs, switch workspace, open admin)
- `Cmd/Ctrl+Enter` send
- `Esc` close modals

### 7. Search-as-you-type over doc names in the sidebar
Filter input above the doc list. Zero backend change needed.

### 8. Per-user rate limit on `/api/query`
Currently any authenticated user can burn your LLM budget. Add a simple token bucket (e.g. 30 queries / 5min / user). Track in memory or Redis.

---

## 🏗️ Medium-term (weeks)

### 9. Document preview pane with page highlighting
Split main pane in two: chat left, PDF viewer right with the cited page auto-scrolled + highlighted. Use `pdf.js`. This is **the** feature that turns "chatbot" into "document analyst."

### 10. OCR fallback for scanned PDFs
Today scanned PDFs fail silently. Add `ocrmypdf` or `pytesseract` as a fallback when `extract_text_from_file` returns empty. Gate behind a user-visible "Running OCR…" status — it's slow.

### 11. Auto-summary + key-entity extraction on upload
When a doc reaches `ready`, generate:
- 3-sentence summary
- Named entities (people, orgs, dates, amounts)
- Key topics

Show at the top when the doc is selected. Also feeds the router for better accuracy.

### 12. Comparison mode
"Compare contracts A, B, C on payment terms." Multi-column layout, one question, parallel answers per doc. Great for legal / procurement.

### 13. Suggested questions per document
When a doc becomes `ready`, the LLM proposes 5 sample questions. Shown in the empty state when the user selects the doc.

### 14. Conversation memory
Pass the last N turns into the synthesis prompt so the bot handles "and what about Q3?" as a follow-up to a Q2 question. Bound tokens carefully.

### 15. Export
Per-chat export as Markdown or PDF. "Share answer" that copies a stable link for teammates in the same workspace.

### 16. Admin: workspace CRUD in UI
Currently workspaces are edited in `state/groups.json` + restart. Add create/rename/delete in the Admin modal. Protect against deleting a workspace with docs in it.

### 17. SSO / SAML / OIDC
For enterprise, drop-in `flask-dance` or `Authlib`. Keep local password auth as fallback. Map IdP groups → workspace IDs.

### 18. Upload via URL / Google Drive / SharePoint
Instead of file upload, paste a link. Ingest + index + cache. Reduces friction massively.

---

## 🌋 Larger (months)

### 19. Multi-modal (images, scanned charts)
PageIndex has a [vision-based variant](https://github.com/VectifyAI/PageIndex) that works on page images directly. Plumb it through so scanned docs, chart screenshots, and diagrams are first-class.

### 20. Table extraction as structured data
For XLSX/PDFs with tables, extract into structured form (JSON rows) so numeric questions get exact arithmetic instead of LLM guesses. Use `pandas` for XLSX, `camelot`/`tabula-py` for PDF tables.

### 21. Agentic tools
Let the LLM call functions: `list_docs`, `get_tree`, `get_pages`, `search_filename`. This is what VectifyAI's [Agentic Vectorless RAG example](https://github.com/VectifyAI/PageIndex/tree/main/examples) does. Better on hard cross-doc reasoning, worse on latency. Opt-in "deep research" mode.

### 22. Versioning
When a user re-uploads the same filename, keep both versions. Show "v2 ← latest" in the doc list. Query defaults to latest; users can pin a version.

### 23. Audit trail
Who queried what, when, with what answer. Separate append-only log (`state/audit.log`) outside the main app-writable directory. Essential for compliance (SOC2, ISO).

### 24. Fine-grained permissions
Beyond groups: document-level tags ("confidential", "pii"), per-user doc sharing inside a workspace, read-only vs upload-allowed roles.

### 25. Analytics dashboard
Query volume per workspace, slowest queries, most-cited documents, router accuracy (did the LLM pick the right doc vs user feedback). Simple SQLite + Chart.js is enough.

### 26. Collaborative chats
Shared threads inside a workspace. Team members can see each other's conversations. Slack-like replies in thread.

### 27. Slack / Teams / WhatsApp bot
Same backend, different frontend. `/ask` command in Slack hits `/api/query`. Great adoption lever — nobody has to "go to the chatbot app"; it comes to them.

### 28. Self-improving feedback loop
Thumbs up/down on every answer. Store in `state/feedback.json`. Use downvotes to surface prompt-tuning opportunities or docs that need better summaries.

### 29. Redaction pre-upload
Client-side or server-side regex-based PII redaction (SSNs, credit cards, emails) before text hits the cache or the LLM. For regulated environments.

### 30. Offline mode
Everything already works with Ollama. Package as a single Electron/Tauri binary for desktop users who can't touch cloud LLMs.

---

## Internal / DX improvements

- **Tests.** No test suite today. Start with `tests/test_api.py` hitting `/health`, `/api/auth/*`, `/api/query` with mocked LLM. `pytest` + `pytest-flask`.
- **CI.** GitHub Actions: lint (`ruff`), syntax check, tests.
- **Deterministic deps.** `pip-compile requirements.in → requirements.txt` with exact versions.
- **Structured logging.** Switch `logging.basicConfig` to JSON logs (`python-json-logger`) so log aggregators (Datadog, Loki) parse them cleanly.
- **Docker.** `Dockerfile` + `docker-compose.yml` wiring up Flask + LiteLLM + (optional) Ollama. Huge onboarding win for open-source users.
- **Health/readiness split.** `/health` today conflates both. Add `/ready` that checks LLM connectivity — lets orchestrators (k8s, systemd) distinguish alive-but-broken from ready.
- **Migrations.** If you ever move from JSON files to SQLite/Postgres, have a data-migration script ready from day 1.

---

## Non-goals (stay disciplined)

- ❌ Vector DB. The whole point is vectorless reasoning.
- ❌ Chunking. Documents stay whole.
- ❌ Hand-rolled auth. Use flask-login or SSO — never roll your own crypto.
- ❌ Multi-tenant across organizations. Workspaces are within one org. Multi-org = different product.
