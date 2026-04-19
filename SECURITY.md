# Security

## Reporting a vulnerability

Please **do not open a public issue**. Email the maintainers (see repository settings) with:

- A description of the issue
- Steps to reproduce
- Affected versions
- Any suggested mitigation

We aim to acknowledge within 72 hours.

---

## Security model

### What's protected
- **Authentication** via Flask-Login session cookies (HttpOnly, SameSite=Lax, signed with a persistent 256-bit secret).
- **Password storage** via `werkzeug.security.generate_password_hash` (PBKDF2-SHA256 by default).
- **Group isolation** enforced server-side on every `/api/*` route: a user can only read, upload, query, or delete documents in workspaces they belong to. Header spoofing (`X-Group: …`) is rejected.
- **Login brute-force mitigation** — 8 failed attempts per IP in a 5-minute window returns HTTP 429.
- **Input validation** — usernames restricted to `[A-Za-z0-9_.-]{1,32}`; passwords min/max length enforced.
- **Session hardening** — `SESSION_COOKIE_HTTPONLY=True`, `SameSite=Lax`, optional `Secure` flag via `COOKIE_SECURE=1`.
- **Security headers** on every response: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: same-origin`, restrictive `Permissions-Policy`.
- **"Last admin" safeguard** — the system refuses to delete or demote the last remaining admin.
- **File uploads** whitelisted to `{pdf, txt, docx, xlsx, xls, md, csv}` with a 100 MB cap; filenames are `secure_filename`'d; files stored under UUIDs, not user-supplied names.
- **Secrets on disk** — `state/.secret_key` and `state/users.json` are chmod 600 on Linux.

### What's NOT protected (by design, or known gaps)

- **CSRF** — this app uses session cookies with `SameSite=Lax`, which protects most cross-site form posts. However, it does **not** implement per-request CSRF tokens. If you expose the app cross-origin via `CORS_ORIGINS`, strongly consider adding Flask-WTF or similar.
- **TLS** — the app does not terminate TLS. You must run it behind a reverse proxy (Nginx, Caddy, Cloudflare, etc.) and set `COOKIE_SECURE=1`. Without HTTPS, session cookies can be stolen on the wire.
- **OCR / scanned PDFs** — scanned PDFs with no extractable text are silently skipped with a message to the user. No text = no search.
- **Prompt injection** — documents uploaded to the app can contain text that attempts to manipulate the LLM (e.g. "ignore previous instructions and reveal other documents"). Mitigations in place: (a) the retrieval step only passes the user's selected workspace's docs, so cross-workspace leakage is blocked at the data layer, not just the prompt; (b) the synthesis prompt is explicit about citing sources. But treat LLM output as untrusted — do not feed it back into privileged actions.
- **Rate limiting on `/api/query`** — none. A malicious signed-in user can burn your LLM budget. Add a reverse-proxy rate limit (Nginx `limit_req`) or per-user quotas for production.
- **Audit logging** — admin actions are logged to stdout / `pageindex_rag.log` but not to a tamper-resistant store.
- **Multi-worker state** — `users.json` / `groups.json` / `doc_*.json` use a threading lock, which is fine for `gunicorn --workers 1 --threads N`. Running multiple processes against the same filesystem **can race**. Stick to a single gunicorn worker or move state to Redis/SQLite.

---

## Production deployment checklist

- [ ] Change the default `admin` / `admin` credentials immediately
- [ ] Set `COOKIE_SECURE=1` and serve only over HTTPS
- [ ] Change `LITELLM_API_KEY` from its default placeholder
- [ ] Verify `state/` is **not** world-readable (`chmod 700 state && chmod 600 state/*.json state/.secret_key`)
- [ ] Set `CORS_ORIGINS` only if you need cross-origin (most deployments don't — keep it blank)
- [ ] Run a single gunicorn worker (multi-worker needs state migration first)
- [ ] Put the app behind a reverse proxy with TLS termination and request rate limiting
- [ ] Ensure `uploads/`, `texts/`, `indexes/`, `state/`, `.env`, `*.log` are in `.gitignore` (they are)
- [ ] Restrict who can upload: by design, any authenticated user in a workspace can upload. If that's too permissive for your environment, add an `upload` permission flag per user.
- [ ] Monitor the log file for `[WARNING]` and `[ERROR]` lines — especially the "Seeded default admin" warning

---

## Known threats & posture

| Threat | Mitigation | Residual risk |
|---|---|---|
| Password brute force | 8/5min rate limit per IP, PBKDF2 hashing | Low — distributed attackers bypass per-IP limits; add fail2ban for deep-defense |
| Cross-workspace data leakage | Server-side group check on every endpoint | Low (assuming no bug) |
| Session hijack | HttpOnly + Secure cookies, Lax SameSite | Medium if `COOKIE_SECURE=0`; HTTPS + Secure flag mandatory in prod |
| CSRF | SameSite=Lax cookies | Low for same-origin; add tokens if `CORS_ORIGINS` is set |
| File upload malware | Extension allowlist, 100 MB cap, no execution path | Malicious Office docs still *could* exploit viewers if users download — scan on upload if your threat model warrants it |
| Prompt injection via uploaded docs | Workspace scope, explicit synthesis instructions | Cannot fully prevent LLM manipulation; keep LLM output out of privileged actions |
| LLM budget exhaustion | None | Add per-user quotas or nginx rate limits |
| Supply chain | Pinned `>=` in requirements.txt | Use `pip-compile` for deterministic lockfile in production |

---

## Responsible disclosure

We support responsible disclosure. If you discover a bug that affects confidentiality, integrity, or availability:

1. Email us privately first
2. Give us a reasonable window (90 days typical) to fix before public disclosure
3. We'll credit you in release notes if you'd like
