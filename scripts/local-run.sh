#!/usr/bin/env bash
# Phase 0: Run the entire stack locally before touching any cloud infra.
# Prerequisites: iii CLI, bun (or node 20), python3.11, pip
# Usage: bash scripts/local-run.sh
set -euo pipefail

QUICKSTART_DIR="$(cd "$(dirname "$0")/../quickstart" && pwd)"

echo "==> Checking prerequisites..."
command -v iii   >/dev/null || { echo "ERROR: iii CLI not found. Install: npm i -g @iii-org/cli"; exit 1; }
command -v bun   >/dev/null || command -v node >/dev/null || { echo "ERROR: bun or node required"; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 required"; exit 1; }

echo "==> Installing caller-worker deps..."
cd "${QUICKSTART_DIR}/workers/caller-worker"
npm install

echo "==> Installing inference-worker deps..."
cd "${QUICKSTART_DIR}/workers/inference-worker"
pip install -r requirements.txt --quiet

echo "==> Starting iii engine + workers..."
cd "${QUICKSTART_DIR}"

# Use local config (127.0.0.1 binding for local dev)
sed -i.bak 's/host: 0.0.0.0/host: 127.0.0.1/' config.yaml || true

# Start engine in background
iii engine start --config config.yaml &
ENGINE_PID=$!
echo "    Engine PID: ${ENGINE_PID}"
sleep 3

# Start inference worker in background
cd workers/inference-worker
python3 inference_worker.py &
INF_PID=$!
echo "    Inference worker PID: ${INF_PID}"
sleep 2

# Start caller worker in background
cd "${QUICKSTART_DIR}/workers/caller-worker"
npm run dev &
CALLER_PID=$!
echo "    Caller worker PID: ${CALLER_PID}"

# Restore cloud config after local run
trap "kill ${ENGINE_PID} ${INF_PID} ${CALLER_PID} 2>/dev/null; \
  sed -i 's/host: 127.0.0.1/host: 0.0.0.0/' ${QUICKSTART_DIR}/config.yaml || true; \
  echo 'Stopped all workers'" EXIT

echo ""
echo "==> Waiting for model to load (~60s for first download)..."
sleep 10

echo "==> Running local smoke test..."
for i in $(seq 1 20); do
  STATUS=$(curl -so /dev/null -w "%{http_code}" \
    http://127.0.0.1:3111/healthz 2>/dev/null || echo "000")
  if [[ "${STATUS}" == "200" ]]; then
    echo "    API ready after ${i} polls"
    break
  fi
  echo "    poll ${i}/20 — waiting..."
  sleep 10
done

echo ""
RESPONSE=$(curl -fsS -X POST http://127.0.0.1:3111/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is 2+2? Answer with just the number."}]}')

echo "Response:"
echo "${RESPONSE}" | jq .
echo ""
echo "==> LOCAL RUN PASSED ✓"
echo "    Press Ctrl+C to stop all services."
wait
