# 📑 PageIndex RAG v2

> **Vectorless, reasoning-based document Q&A** — powered by PageIndex + Claude or Ollama.  
> Upload PDFs, Word docs, spreadsheets, and text files. Ask questions in plain English. Get cited answers.

![Python](https://img.shields.io/badge/Python-3.12+-blue?logo=python&logoColor=white)
![Flask](https://img.shields.io/badge/Flask-3.0-black?logo=flask)
![License](https://img.shields.io/badge/License-MIT-green)
![LLM](https://img.shields.io/badge/LLM-Claude%20%7C%20Ollama-purple)

---

## ✨ Features

| Feature | Details |
|---|---|
| 🗂 **Multi-format** | PDF, DOCX, XLSX, XLS, TXT, MD, CSV |
| 🔍 **Vectorless RAG** | PageIndex tree navigation — no embeddings, no vector DB |
| 🤖 **LLM choice** | Claude (via LiteLLM) or Ollama (fully local) |
| 🏢 **Workspaces** | HR / IT / Developers — docs isolated per group |
| 🔐 **Auth** | flask-login sessions, rate-limited login, HttpOnly cookies |
| 👥 **Admin UI** | Create users, assign workspaces, manage docs |
| 📊 **Smart Excel** | Searches across all sheets, not just the first |
| 💬 **Auto-routing** | Query routes to relevant docs automatically — no need to pick |
| 🔄 **Persistent state** | File-based — survives restarts, no Redis/DB needed |

---

## 🖥 Screenshots

```
┌─────────────────────────────────────────────────────┐
│  📑 PageIndex RAG v2   [HR ▾]  Claude · Sonnet  ●  │
├──────────────┬──────────────────────────────────────┤
│  Documents   │  Chat                                │
│  ─────────── │  ────────────────────────────────    │
│  ⬆ Upload   │  AI: Ready! Ask me anything.         │
│              │                                      │
│  📄 AMC.pdf  │  You: What is the AMC cost?          │
│  📊 Q3.xlsx  │                                      │
│  📝 SLA.docx │  AI: The AMC amount is ₹2,64,600/-  │
│              │  [AMC.pdf · p.1]                     │
└──────────────┴──────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Prerequisites

- Python 3.12+
- [uv](https://docs.astral.sh/uv/) (fast package manager)
- Claude API key **or** Ollama
- Linux (Ubuntu 22.04+ recommended)

---

### 1. Install uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env    # add uv to PATH
uv --version                   # verify: uv x.x.x
```

---

### 2. Clone this repo

```bash
git clone https://github.com/Harinath-Rajendran/pageindex-rag.git
cd pageindex-rag
```

---

### 3. Clone PageIndex (PDF tree builder)

PageIndex builds a hierarchical tree index from PDFs for precision section navigation.

```bash
git clone https://github.com/VectifyAI/PageIndex.git /PageIndex
cd /PageIndex

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate

cd -    # back to pageindex-rag
```

> **Optional:** If you skip PageIndex, the app still works — it falls back to full-text extraction for PDFs. All other formats are unaffected.

---

### 4. Install dependencies

```bash
uv venv venv --python 3.12
source venv/bin/activate
uv pip install -r requirements.txt
```

---

### 5. Configure

```bash
cp .env.example .env
nano .env
```

**Minimum config for Claude:**
```env
LLM_MODE=claude
ANTHROPIC_API_KEY=sk-ant-your-key-here
```

**Minimum config for Ollama (fully local):**
```env
LLM_MODE=ollama
OLLAMA_MODEL=gemma3:4b
```

---

### 6. Run (development)

```bash
# Terminal 1 — LiteLLM proxy (Claude only, skip for Ollama)
litellm --config litellm_config.yaml --port 4000

# Terminal 2 — Flask app
export $(grep -v '^#' .env | xargs)
python app.py
```

Open **http://localhost:5000** — login with `admin` / `admin` and **change the password immediately**.

---

## 🏭 Production Deployment (systemd)

```bash
sudo bash setup.sh

# Start services
sudo systemctl start litellm-proxy    # Claude only — skip for Ollama
sudo systemctl start pageindex-rag

# Check status
sudo systemctl status pageindex-rag
journalctl -fu pageindex-rag
```

The setup script creates two systemd services that auto-restart on failure and start on boot.

---

## 🦙 Using Ollama (Fully Local)

No API key, no internet required after model download.

```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Pull recommended model (4GB RAM, best quality/size ratio)
ollama pull gemma3:4b

# Set in .env
LLM_MODE=ollama
OLLAMA_MODEL=gemma3:4b

# Restart app
systemctl restart pageindex-rag
```

**Other lightweight models:**

| Model | RAM | Best for |
|---|---|---|
| `gemma3:4b` | 4 GB | General Q&A, recommended |
| `qwen2.5:3b` | 3 GB | Fast, good at structured data |
| `llama3.2:3b` | 3 GB | Balanced |
| `phi4-mini` | 3.5 GB | Reasoning tasks |

---

## 📁 Supported File Formats

| Format | Extension | Notes |
|---|---|---|
| PDF | `.pdf` | Text-based PDFs; scanned PDFs need OCR (not yet supported) |
| Word | `.docx` | Full text + tables |
| Excel | `.xlsx`, `.xls` | All sheets searched |
| Text | `.txt`, `.md` | Plain text and Markdown |
| CSV | `.csv` | Comma-separated data |

---

## 🏢 Workspaces (Groups)

Documents are isolated per workspace. Default workspaces:

| Workspace | ID | Description |
|---|---|---|
| HR | `hr` | Human Resources docs |
| IT | `it` | IT / InfoSec docs |
| Developers | `developers` | Engineering docs |

Admins can manage users and assign them to workspaces via the **Admin** button in the UI.

---

## 🔐 Security Notes

- Default admin credentials (`admin`/`admin`) — **change immediately after first login**
- Set `COOKIE_SECURE=1` when running behind HTTPS
- Set a strong `LITELLM_API_KEY` in production
- `state/users.json` and `state/.secret_key` are chmod 600 automatically
- Login is rate-limited: 8 failed attempts / 5 min / IP → 429

---

## 🗂 Project Structure

```
pageindex-rag/
├── app.py                  # Flask backend (~1000 lines)
├── static/
│   └── index.html          # Single-file SPA frontend
├── litellm_config.yaml     # LiteLLM proxy config (Claude routing)
├── setup.sh                # Systemd service installer
├── pyproject.toml          # Python project metadata (uv)
├── requirements.txt        # Pinned dependencies
├── .env.example            # Environment variable template
├── .gitignore
├── README.md
└── CLAUDE.md               # Claude Code guidance

# Auto-created at runtime (gitignored):
├── uploads/                # Raw uploaded files
├── texts/                  # Extracted text cache
├── indexes/                # PageIndex trees (PDF)
└── state/                  # JSON state (users, docs, jobs)
```

---

## ⚙️ Environment Variables

| Variable | Default | Description |
|---|---|---|
| `LLM_MODE` | `claude` | `claude` or `ollama` |
| `ANTHROPIC_API_KEY` | — | Claude API key |
| `LITELLM_BASE_URL` | `http://localhost:4000` | LiteLLM proxy URL |
| `LITELLM_API_KEY` | `sk-placeholder` | LiteLLM auth token |
| `QUERY_MODEL` | `claude-sonnet` | Model for answering |
| `INDEX_MODEL` | `claude-sonnet` | Model for PDF indexing |
| `PAGEINDEX_DIR` | `/PageIndex` | PageIndex repo path |
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Ollama server URL |
| `OLLAMA_MODEL` | `gemma3:4b` | Ollama model name |
| `COOKIE_SECURE` | `0` | `1` = HTTPS-only cookies |
| `CORS_ORIGINS` | `` | Allowed origins (blank = same-origin) |
| `PORT` | `5000` | Flask listen port |

---

## 🔧 Troubleshooting

**Documents disappear after upload**
→ Check gunicorn worker count. Use `--workers 1 --threads 4` (state is file-based, not shared memory).

**"OCR not yet supported" error**
→ Your PDF is a scanned image. Convert to text-based PDF first using tools like Adobe Acrobat or `ocrmypdf`.

**LiteLLM fails to start**
→ Run `pip install 'litellm[proxy]' websockets` in the venv. Check `journalctl -fu litellm-proxy`.

**PageIndex not found**
→ Clone it to `/PageIndex` (step 3) or set `PAGEINDEX_DIR` in `.env` to the correct path.

**uv not found after install**
→ Run `source $HOME/.local/bin/env` or add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc`.

**Sessions not persisting**
→ Behind HTTPS? Set `COOKIE_SECURE=1`. Otherwise sessions silently fail.

---

## 📜 License

MIT — see [LICENSE](LICENSE).

---

## 🙏 Credits

- [PageIndex](https://github.com/VectifyAI/PageIndex) by VectifyAI — vectorless document tree indexing
- [LiteLLM](https://github.com/BerriAI/litellm) — OpenAI-compatible proxy for Claude and 100+ models
- [Ollama](https://ollama.com) — run LLMs locally

---

*Built by [Harinath Rajendran](https://github.com/Harinath-Rajendran)*
