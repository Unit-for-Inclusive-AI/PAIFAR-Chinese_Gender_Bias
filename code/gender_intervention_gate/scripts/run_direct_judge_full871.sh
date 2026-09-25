#!/usr/bin/env bash

# Score successful Direct Zero-shot outputs with Frozen Rewrite Judge v04 Balanced.
# - Reads only current runs/ directories.
# - Ignores rows with error or blank final_output.
# - Does not modify original writer runs.
# - Uses an isolated Judge cache.
# - Supports START_FROM=1..11 and CACHE_MODE=clean|reuse.

set -uo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../pyproject.toml" ]]; then
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
elif [[ -f "$(pwd)/pyproject.toml" ]]; then
  ROOT="$(pwd)"
else
  echo "ERROR: Cannot locate project root containing pyproject.toml." >&2
  exit 1
fi
cd "$ROOT"

if [[ -f .venv/bin/activate ]]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi

TYPE_MAP="${TYPE_MAP:-data/review/rewrite_type_map_positive_full871.csv}"
BASE_CONFIG="configs/judge/rewrite_judge_v04_balanced_gpt4o.yaml"
GENERATED_CONFIG="configs/generated/rewrite_judge_v04_direct_full871.yaml"
CACHE_DB=".cache/judge_v04/direct_positive_full871.sqlite"
CACHE_MODE="${CACHE_MODE:-clean}"
START_FROM="${START_FROM:-1}"
CONCURRENCY="${JUDGE_CONCURRENCY:-5}"
RUN_TAG="$(date +%Y%m%d_%H%M%S)"
INPUT_ROOT="data/review/positive_full871/direct_zero_shot"
LOG_ROOT="logs/judge_positive_full871/direct_zero_shot/${RUN_TAG}"
INDEX_FILE="${LOG_ROOT}/run_index.tsv"

ALIASES=(
  openai
  gemini
  qwen_api
  glm_api
  qwen3_5_9b_ollama
  glm4_9b_ollama
  gemma2_9b_ollama
  llama3_1_8b_ollama
  mistral_7b_ollama
  deepseek_v4_pro
  deepseek_r1_8b_ollama
)

if ! [[ "$START_FROM" =~ ^([1-9]|1[01])$ ]]; then
  echo "ERROR: START_FROM must be an integer from 1 to 11." >&2
  exit 1
fi
if ! [[ "$CONCURRENCY" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: JUDGE_CONCURRENCY must be a positive integer." >&2
  exit 1
fi

for required in "$TYPE_MAP" "$BASE_CONFIG" scripts/run_rewrite_judge.py; do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: Required file not found: $required" >&2
    if [[ "$required" == "$TYPE_MAP" ]]; then
      echo "Frozen Judge v04 cannot run without the full 871-item rewrite-type map." >&2
    fi
    exit 1
  fi
done

mkdir -p "$(dirname "$GENERATED_CONFIG")" "$INPUT_ROOT" "$LOG_ROOT" "$(dirname "$CACHE_DB")"

# Validate the frozen type map before spending Judge calls.
python - "$TYPE_MAP" <<'PY'
import csv
import sys
from collections import Counter

path = sys.argv[1]
with open(path, encoding="utf-8-sig", newline="") as f:
    rows = list(csv.DictReader(f))

allowed = {"LOCAL_REPAIR", "PROPOSITION_RECONSTRUCTION"}
ids = [str(r.get("id", "")).strip() for r in rows]
types = [str(r.get("rewrite_type", "")).strip() for r in rows]
errors = []
if len(rows) != 871:
    errors.append(f"expected 871 rows, got {len(rows)}")
if len(set(ids)) != len(ids):
    errors.append("duplicate ids detected")
invalid = [(i, t) for i, t in zip(ids, types) if t not in allowed]
if invalid:
    errors.append(f"invalid or blank rewrite_type for {len(invalid)} rows; first={invalid[:5]}")
if errors:
    raise SystemExit("TYPE MAP INVALID: " + "; ".join(errors))
print("Type map valid: 871 unique rows")
print("Type counts:", dict(Counter(types)))
PY

# Generate an isolated Judge config.
python - "$BASE_CONFIG" "$GENERATED_CONFIG" "$CACHE_DB" "$CONCURRENCY" <<'PY'
import sys
from pathlib import Path
import yaml

source, output, cache_db, concurrency = sys.argv[1:]
cfg = yaml.safe_load(Path(source).read_text(encoding="utf-8"))
cfg["name"] = "rewrite_judge_v04_balanced_direct_positive_full871"
cfg["cache_db"] = cache_db
cfg["concurrency"] = int(concurrency)
Path(output).write_text(
    yaml.safe_dump(cfg, allow_unicode=True, sort_keys=False),
    encoding="utf-8",
)
print("Generated Judge config:", output)
print("Judge model key:", cfg.get("model_key"))
print("Judge cache:", cache_db)
PY

case "$CACHE_MODE" in
  clean)
    if pgrep -f "[r]un_rewrite_judge.py" >/dev/null 2>&1; then
      echo "ERROR: Another run_rewrite_judge.py process is active." >&2
      echo "Stop it before cleaning the shared Direct Judge cache." >&2
      exit 1
    fi
    if [[ -f "$CACHE_DB" || -f "${CACHE_DB}-wal" || -f "${CACHE_DB}-shm" ]]; then
      BACKUP_DIR="cache_backup/judge_direct_full871_${RUN_TAG}"
      mkdir -p "$BACKUP_DIR"
      for f in "$CACHE_DB" "${CACHE_DB}-wal" "${CACHE_DB}-shm"; do
        [[ -f "$f" ]] && cp -p "$f" "$BACKUP_DIR/"
      done
      rm -f "$CACHE_DB" "${CACHE_DB}-wal" "${CACHE_DB}-shm"
      echo "Old Direct Judge cache backed up to: $BACKUP_DIR"
    else
      echo "No previous Direct Judge cache found."
    fi
    ;;
  reuse)
    echo "CACHE_MODE=reuse: retaining existing Direct Judge cache."
    ;;
  *)
    echo "ERROR: CACHE_MODE must be clean or reuse." >&2
    exit 1
    ;;
esac

printf "order\tmodel_alias\twriter_run\tscored_n\twriter_failures\tjudge_status\tjudge_errors\tjudge_run\tlog\n" > "$INDEX_FILE"

prepare_input() {
  local writer_run="$1"
  local output_csv="$2"
  python - "$writer_run/predictions.jsonl" "$TYPE_MAP" "$output_csv" <<'PY'
import csv
import json
import sys
from pathlib import Path

pred_path, type_path, out_path = map(Path, sys.argv[1:])
predictions = [
    json.loads(line)
    for line in pred_path.read_text(encoding="utf-8").splitlines()
    if line.strip()
]
with type_path.open(encoding="utf-8-sig", newline="") as f:
    type_rows = list(csv.DictReader(f))
types = {r["id"].strip(): r["rewrite_type"].strip() for r in type_rows}

seen = set()
rows = []
failures = 0
for p in predictions:
    item_id = str(p.get("id", "")).strip()
    if not item_id or item_id in seen:
        raise SystemExit(f"Invalid or duplicate prediction id: {item_id!r}")
    seen.add(item_id)
    output = str(p.get("final_output") or "").strip()
    if p.get("error") or not output:
        failures += 1
        continue
    rewrite_type = types.get(item_id)
    if not rewrite_type:
        raise SystemExit(f"Missing rewrite_type for successful item {item_id}")
    rows.append({
        "id": item_id,
        "text": str(p.get("text") or ""),
        "output": output,
        "rewrite_type": rewrite_type,
        "type_note": "",
    })

if len(predictions) != 871 or len(seen) != 871:
    raise SystemExit(
        f"Writer run is not full871: rows={len(predictions)}, unique={len(seen)}"
    )
if not rows:
    raise SystemExit("No successful writer outputs available for Judge input")

out_path.parent.mkdir(parents=True, exist_ok=True)
with out_path.open("w", encoding="utf-8-sig", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)

print(f"{len(rows)}\t{failures}")
PY
}

for idx in "${!ALIASES[@]}"; do
  order=$((idx + 1))
  alias="${ALIASES[$idx]}"

  if (( order < START_FROM )); then
    printf "%02d\t%s\t-\t-\t-\tSKIPPED\t-\t-\tbefore START_FROM=%s\n" \
      "$order" "$alias" "$START_FROM" >> "$INDEX_FILE"
    echo "[$order/11] SKIP $alias (before START_FROM=$START_FROM)"
    continue
  fi

  matches=(runs/*_rewriter_direct_zero_shot_${alias}_positive_full871)
  if (( ${#matches[@]} == 0 )); then
    echo "ERROR: No Direct writer run found for $alias in runs/." >&2
    printf "%02d\t%s\t-\t-\t-\tMISSING_WRITER_RUN\t-\t-\t-\n" \
      "$order" "$alias" >> "$INDEX_FILE"
    continue
  fi
  if (( ${#matches[@]} > 1 )); then
    echo "ERROR: Multiple Direct writer runs found for $alias:" >&2
    printf '  %s\n' "${matches[@]}" >&2
    echo "Move superseded/interrupted directories out of runs/ before scoring." >&2
    exit 1
  fi

  writer_run="${matches[0]}"
  input_csv="${INPUT_ROOT}/${alias}.csv"
  prep_result="$(prepare_input "$writer_run" "$input_csv")"
  scored_n="${prep_result%%$'\t'*}"
  writer_failures="${prep_result##*$'\t'}"
  run_name="direct_zero_shot_${alias}_positive_full871_judge_v04"
  log_file="${LOG_ROOT}/${order}_${run_name}.log"

  echo
  echo "================================================================================"
  echo "[$order/11] Judge Direct: $alias"
  echo "Writer run:      $writer_run"
  echo "Judge input:     $input_csv"
  echo "Scored N:        $scored_n"
  echo "Writer failures: $writer_failures"
  echo "Judge config:    $GENERATED_CONFIG"
  echo "Log:             $log_file"
  echo "================================================================================"

  set +e
  python -u scripts/run_rewrite_judge.py \
    --config "$GENERATED_CONFIG" \
    --input "$input_csv" \
    --concurrency "$CONCURRENCY" \
    --name "$run_name" \
    2>&1 | tee "$log_file"
  code=${PIPESTATUS[0]}
  set -e

  judge_run="$(grep '^Run directory:' "$log_file" | tail -1 | sed 's/^Run directory: //')"
  if [[ "$code" -ne 0 || -z "$judge_run" || ! -f "$judge_run/metrics.json" ]]; then
    printf "%02d\t%s\t%s\t%s\t%s\tFAILED\t-\t%s\t%s\n" \
      "$order" "$alias" "$writer_run" "$scored_n" "$writer_failures" \
      "${judge_run:--}" "$log_file" >> "$INDEX_FILE"
    echo "FAILED: Judge run for $alias (exit code=$code). Continuing."
    continue
  fi

  judge_errors="$(python - "$judge_run/metrics.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1],encoding='utf-8'))
print(m['overall']['error_count'])
PY
)"
  status="SUCCESS"
  [[ "$judge_errors" != "0" ]] && status="SUCCESS_WITH_JUDGE_ERRORS"
  printf "%02d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$order" "$alias" "$writer_run" "$scored_n" "$writer_failures" \
    "$status" "$judge_errors" "$judge_run" "$log_file" >> "$INDEX_FILE"
done

echo
echo "================================================================================"
echo "Direct Judge suite finished."
echo "Index: $INDEX_FILE"
echo "================================================================================"
if command -v column >/dev/null 2>&1; then
  column -t -s $'\t' "$INDEX_FILE"
else
  cat "$INDEX_FILE"
fi
