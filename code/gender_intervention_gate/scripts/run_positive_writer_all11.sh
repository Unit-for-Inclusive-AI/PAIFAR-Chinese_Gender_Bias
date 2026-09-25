#!/usr/bin/env bash

# Full Golden Positive (871 examples) rewriting experiment for 11 models.
# Supported modes:
#   MODE=direct  -> prompts/rewrite_original_direct.txt
#   MODE=v2      -> prompts/rewriter_v02_semantic_preserving.txt
#
# Results are timestamped under runs/ and never overwrite older runs.
# Direct and V2 use separate SQLite caches and separate log directories.
# DeepSeek API and local DeepSeek-R1 are intentionally placed last.
# START_FROM=N skips models before N (1..11), useful for resuming without replay.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../pyproject.toml" ]]; then
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
elif [[ -f "$(pwd)/pyproject.toml" ]]; then
  ROOT="$(pwd)"
else
  echo "ERROR: Cannot locate project root containing pyproject.toml."
  echo "Save this script under scripts/ or run it from the project root."
  exit 1
fi
cd "$ROOT"

if [[ -f ".venv/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
  echo "Activated: $ROOT/.venv"
else
  echo "WARNING: .venv/bin/activate not found; using current Python environment."
fi

MODE="${MODE:-}"
CACHE_MODE="${CACHE_MODE:-clean}"
API_CONCURRENCY="${API_CONCURRENCY:-3}"
LOCAL_CONCURRENCY="${LOCAL_CONCURRENCY:-1}"
START_FROM="${START_FROM:-1}"

if [[ ! "$START_FROM" =~ ^[0-9]+$ ]] || (( START_FROM < 1 || START_FROM > 11 )); then
  echo "ERROR: START_FROM must be an integer from 1 to 11."
  echo "Example: START_FROM=3 MODE=direct CACHE_MODE=reuse bash scripts/run_positive_writer_all11.sh"
  exit 1
fi

case "$MODE" in
  direct)
    BASE_CONFIG="configs/rewriter/rewriter_v01_gpt4o.yaml"
    GENERATED_CONFIG="configs/generated/positive_full871_direct.yaml"
    CONDITION_NAME="direct_zero_shot"
    CACHE_DB=".cache/positive_full871/direct_zero_shot.sqlite"
    ;;
  v2)
    BASE_CONFIG="configs/rewriter/rewriter_v02_gpt4o.yaml"
    GENERATED_CONFIG="configs/generated/positive_full871_v2.yaml"
    CONDITION_NAME="v2_prompt"
    CACHE_DB=".cache/positive_full871/v2_prompt.sqlite"
    ;;
  *)
    echo "ERROR: Set MODE=direct or MODE=v2."
    echo "Example: MODE=direct CACHE_MODE=clean caffeinate -dimsu bash scripts/run_positive_writer_all11.sh"
    exit 1
    ;;
esac

SOURCE_DATA="data/processed/main.jsonl"
POSITIVE_DATA="data/processed/positive_full_871.jsonl"
RUN_TAG="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="logs/positive_full871/${CONDITION_NAME}/${RUN_TAG}"
STATUS_FILE="${LOG_DIR}/status.tsv"
CACHE_BACKUP_DIR="cache_backup/positive_full871/${CONDITION_NAME}/${RUN_TAG}"

mkdir -p "$LOG_DIR" "configs/generated" "$(dirname "$CACHE_DB")"

for required in \
  "$SOURCE_DATA" \
  "$BASE_CONFIG" \
  "configs/models.yaml" \
  "scripts/run_rewriter_experiment.py"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: Required file not found: $required"
    exit 1
  fi
done

# -----------------------------------------------------------------------------
# Build and validate the complete 871-item POSITIVE JSONL.
# -----------------------------------------------------------------------------
python - "$SOURCE_DATA" "$POSITIVE_DATA" <<'PY'
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
output = Path(sys.argv[2])
rows = [
    json.loads(line)
    for line in source.read_text(encoding="utf-8").splitlines()
    if line.strip()
]
positive = [row for row in rows if row.get("label") == "POSITIVE"]

if len(positive) != 871:
    raise SystemExit(f"Expected 871 POSITIVE items, found {len(positive)}")
ids = [str(row.get("id", "")) for row in positive]
if len(set(ids)) != 871 or any(not item_id for item_id in ids):
    raise SystemExit("POSITIVE data contains duplicate or empty IDs")

output.parent.mkdir(parents=True, exist_ok=True)
tmp = output.with_suffix(output.suffix + ".tmp")
with tmp.open("w", encoding="utf-8") as handle:
    for row in positive:
        handle.write(json.dumps(row, ensure_ascii=False) + "\n")
tmp.replace(output)
print(f"Prepared {len(positive)} POSITIVE items: {output}")
PY

# -----------------------------------------------------------------------------
# Create an isolated generated config without modifying the frozen originals.
# -----------------------------------------------------------------------------
python - "$BASE_CONFIG" "$GENERATED_CONFIG" "$POSITIVE_DATA" "$CACHE_DB" "$CONDITION_NAME" <<'PY'
import sys
from pathlib import Path
import yaml

base_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
split = sys.argv[3]
cache_db = sys.argv[4]
condition = sys.argv[5]

config = yaml.safe_load(base_path.read_text(encoding="utf-8"))
config["name"] = f"{condition}_positive_full871"
config["split"] = split
config["cache_db"] = cache_db
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(
    yaml.safe_dump(config, allow_unicode=True, sort_keys=False),
    encoding="utf-8",
)
print(f"Generated isolated config: {out_path}")
print(f"Prompt: {config['prompt']}")
print(f"Max output tokens: {config['max_output_tokens']}")
print(f"Cache DB: {config['cache_db']}")
PY

# -----------------------------------------------------------------------------
# Cache policy for this condition only. The Gate cache and other caches are not
# touched.
# -----------------------------------------------------------------------------
case "$CACHE_MODE" in
  clean)
    if pgrep -f "[s]cripts/run_rewriter_experiment.py" >/dev/null 2>&1; then
      echo "ERROR: Another run_rewriter_experiment.py process is active."
      echo "Stop it before cleaning the condition-specific cache."
      exit 1
    fi

    CACHE_FILES=("$CACHE_DB" "${CACHE_DB}-wal" "${CACHE_DB}-shm")
    CACHE_FOUND=0
    for file in "${CACHE_FILES[@]}"; do
      [[ -f "$file" ]] && CACHE_FOUND=1
    done

    if [[ "$CACHE_FOUND" -eq 1 ]]; then
      mkdir -p "$CACHE_BACKUP_DIR"
      for file in "${CACHE_FILES[@]}"; do
        [[ -f "$file" ]] && cp -p "$file" "$CACHE_BACKUP_DIR/"
      done
      rm -f "${CACHE_FILES[@]}"
      echo "Backed up old condition cache to: $CACHE_BACKUP_DIR"
      echo "Cleared condition cache: $CACHE_DB"
    else
      echo "No existing condition cache found; starting fresh."
    fi
    ;;
  reuse)
    echo "CACHE_MODE=reuse: existing condition cache will be reused."
    ;;
  *)
    echo "ERROR: CACHE_MODE must be clean or reuse."
    exit 1
    ;;
esac

printf "order\tmodel_key\trun_name\tstatus\texit_code\tlog_file\n" > "$STATUS_FILE"

run_writer() {
  local order="$1"
  local model_key="$2"
  local model_label="$3"
  local concurrency="$4"
  shift 4

  local run_name="${CONDITION_NAME}_${model_label}_positive_full871"
  local log_file="${LOG_DIR}/${order}_${run_name}.log"

  echo
  echo "================================================================================"
  echo "[$order/11] $CONDITION_NAME — $model_key"
  echo "Run name:    $run_name"
  echo "Dataset:     $POSITIVE_DATA"
  echo "Config:      $GENERATED_CONFIG"
  echo "Concurrency: $concurrency"
  echo "Log:         $log_file"
  echo "Started:     $(date)"
  echo "================================================================================"

  python -u scripts/run_rewriter_experiment.py \
    --config "$GENERATED_CONFIG" \
    --model-key "$model_key" \
    --concurrency "$concurrency" \
    --name "$run_name" \
    "$@" \
    2>&1 | tee "$log_file"

  local code=${PIPESTATUS[0]}
  if [[ "$code" -eq 0 ]]; then
    printf "%s\t%s\t%s\tSUCCESS\t%s\t%s\n" \
      "$order" "$model_key" "$run_name" "$code" "$log_file" >> "$STATUS_FILE"
    echo "SUCCESS: $model_key"
  else
    printf "%s\t%s\t%s\tFAILED\t%s\t%s\n" \
      "$order" "$model_key" "$run_name" "$code" "$log_file" >> "$STATUS_FILE"
    echo "FAILED: $model_key (exit code=$code); continuing."
  fi
}

record_skipped() {
  local order="$1"
  local model_key="$2"
  local model_label="$3"
  local reason="$4"
  local run_name="${CONDITION_NAME}_${model_label}_positive_full871"
  printf "%s\t%s\t%s\tSKIPPED\t-\t%s\n" \
    "$order" "$model_key" "$run_name" "$reason" >> "$STATUS_FILE"
}

should_run() {
  local order="$1"
  local order_num=$((10#$order))
  (( order_num >= START_FROM ))
}

run_or_skip() {
  local order="$1"
  local model_key="$2"
  local model_label="$3"
  local concurrency="$4"
  shift 4

  if should_run "$order"; then
    run_writer "$order" "$model_key" "$model_label" "$concurrency" "$@"
  else
    record_skipped "$order" "$model_key" "$model_label" "before START_FROM=$START_FROM"
    echo "SKIPPED [$order/11] $model_key — before START_FROM=$START_FROM"
  fi
}

echo
cat <<HEADER
================================================================================
Golden Positive Full871 Writer Experiment
Condition:       $CONDITION_NAME
Dataset:         $POSITIVE_DATA
Models:          11
Start from:      $START_FROM
API concurrency: $API_CONCURRENCY
Local concurrency: $LOCAL_CONCURRENCY
Cache mode:      $CACHE_MODE
Cache DB:        $CACHE_DB
Logs:            $LOG_DIR
================================================================================
HEADER

# 1–4: API models except DeepSeek.
run_or_skip "01" "openai" "openai" "$API_CONCURRENCY"
run_or_skip "02" "gemini" "gemini" "$API_CONCURRENCY"
run_or_skip \
  "03" \
  "qwen" \
  "qwen_api" \
  "$API_CONCURRENCY" \
  --max-output-tokens 4096 \
  --thinking-budget 1536
run_or_skip \
  "04" \
  "glm" \
  "glm_api" \
  "$API_CONCURRENCY" \
  --max-output-tokens 4096

# Check Ollama once. DeepSeek API still runs even if Ollama is unavailable.
LOCAL_AVAILABLE=1
LOCAL_REASON=""
if ! command -v ollama >/dev/null 2>&1; then
  LOCAL_AVAILABLE=0
  LOCAL_REASON="ollama command not found"
elif ! ollama list >/dev/null 2>&1; then
  LOCAL_AVAILABLE=0
  LOCAL_REASON="Ollama service is not running"
else
  echo
  echo "Installed Ollama models:"
  ollama list
fi

# 5–9: Faster local models.
if [[ "$LOCAL_AVAILABLE" -eq 1 ]]; then
  run_or_skip "05" "qwen3_5_9b_ollama" "qwen3_5_9b_ollama" "$LOCAL_CONCURRENCY"
  run_or_skip "06" "glm4_9b_ollama" "glm4_9b_ollama" "$LOCAL_CONCURRENCY"
  run_or_skip "07" "gemma2_9b_ollama" "gemma2_9b_ollama" "$LOCAL_CONCURRENCY"
  run_or_skip "08" "llama3_1_8b_ollama_rewriter" "llama3_1_8b_ollama" "$LOCAL_CONCURRENCY"
  run_or_skip "09" "mistral_7b_ollama" "mistral_7b_ollama" "$LOCAL_CONCURRENCY"
else
  echo "Local models unavailable: $LOCAL_REASON"
  for entry in \
    "05|qwen3_5_9b_ollama|qwen3_5_9b_ollama" \
    "06|glm4_9b_ollama|glm4_9b_ollama" \
    "07|gemma2_9b_ollama|gemma2_9b_ollama" \
    "08|llama3_1_8b_ollama_rewriter|llama3_1_8b_ollama" \
    "09|mistral_7b_ollama|mistral_7b_ollama"
  do
    IFS='|' read -r order model_key model_label <<< "$entry"
    if should_run "$order"; then
      record_skipped "$order" "$model_key" "$model_label" "$LOCAL_REASON"
    else
      record_skipped "$order" "$model_key" "$model_label" "before START_FROM=$START_FROM"
    fi
  done
fi

# 10: Slow DeepSeek API. Force the exact Pro model.
run_or_skip "10" "deepseek" "deepseek_v4_pro" "$API_CONCURRENCY" \
  --model "deepseek-v4-pro"

# 11: Slow local DeepSeek-R1, non-thinking profile from models.yaml.
if should_run "11"; then
  if [[ "$LOCAL_AVAILABLE" -eq 1 ]]; then
    run_writer \
      "11" \
      "deepseek_r1_8b_ollama" \
      "deepseek_r1_8b_ollama" \
      "$LOCAL_CONCURRENCY" \
      --max-output-tokens 2048
  else
    record_skipped "11" "deepseek_r1_8b_ollama" "deepseek_r1_8b_ollama" "$LOCAL_REASON"
  fi
else
  record_skipped "11" "deepseek_r1_8b_ollama" "deepseek_r1_8b_ollama" "before START_FROM=$START_FROM"
  echo "SKIPPED [11/11] deepseek_r1_8b_ollama — before START_FROM=$START_FROM"
fi

echo
echo "================================================================================"
echo "All requested runs finished or were attempted."
echo "Completed:   $(date)"
echo "Status file: $STATUS_FILE"
echo "================================================================================"

if command -v column >/dev/null 2>&1; then
  column -t -s $'\t' "$STATUS_FILE"
else
  cat "$STATUS_FILE"
fi

echo
echo "Matching result directories:"
find runs -maxdepth 1 -type d -name "*_rewriter_${CONDITION_NAME}_*_positive_full871" -print | sort || true
