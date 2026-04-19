#!/bin/bash
# setup.sh — PageIndex RAG v2 setup using uv
# Run: sudo bash setup.sh

set -e
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== PageIndex RAG v2 Setup (uv) ==="

# ── 1. Install uv if missing ───────────────────────────────────────────────
if ! command -v uv &>/dev/null; then
  echo "[1/6] Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
else
  echo "[1/6] uv already installed: $(uv --version)"
fi

# ── 2. Create venv with uv ────────────────────────────────────────────────
echo "[2/6] Creating venv with uv..."
cd "$PROJECT_DIR"
uv venv venv --python 3.12
echo "    ✓ venv ready"

# ── 3. Install dependencies ───────────────────────────────────────────────
echo "[3/6] Installing dependencies..."
uv pip install --python venv/bin/python3 -r pyproject.toml 2>/dev/null || \
uv pip install --python venv/bin/python3 \
  flask flask-cors openai "litellm[proxy]" websockets werkzeug gunicorn \
  pymupdf python-docx openpyxl striprtf chardet
echo "    ✓ Dependencies installed"

# ── 4. Directories ────────────────────────────────────────────────────────
echo "[4/6] Creating directories..."
mkdir -p "$PROJECT_DIR/static" "$PROJECT_DIR/uploads" \
         "$PROJECT_DIR/indexes" "$PROJECT_DIR/state" "$PROJECT_DIR/texts"
echo "    ✓ Done"

# ── 5. Systemd: LiteLLM proxy ─────────────────────────────────────────────
echo "[5/6] Creating systemd services..."
cat > /etc/systemd/system/litellm-proxy.service << EOF
[Unit]
Description=LiteLLM Proxy (Claude API Bridge)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=$PROJECT_DIR/venv/bin/litellm --config $PROJECT_DIR/litellm_config.yaml --port 4000
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# ── 6. Systemd: Flask app ─────────────────────────────────────────────────
cat > /etc/systemd/system/pageindex-rag.service << EOF
[Unit]
Description=PageIndex RAG v2
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=$PROJECT_DIR/venv/bin/gunicorn app:app \\
    --workers 1 \\
    --threads 4 \\
    --bind 0.0.0.0:5000 \\
    --timeout 300 \\
    --access-logfile - \\
    --error-logfile -
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable litellm-proxy pageindex-rag
echo "    ✓ Services created"

echo ""
echo "=== Setup Complete ==="
echo "Next steps:"
echo "  1. cp .env.example .env && nano .env   # add your API key"
echo "  2. systemctl start litellm-proxy        # skip if using Ollama"
echo "  3. systemctl start pageindex-rag"
echo "  4. Open http://$(hostname -I | awk '{print $1}'):5000"
echo ""
echo "  For Ollama: set LLM_MODE=ollama in .env, then:"
echo "    ollama pull gemma3:4b"
echo "    ollama serve"
