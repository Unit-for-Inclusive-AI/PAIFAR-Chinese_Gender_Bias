#!/usr/bin/env python3
"""Summarize the 11-model full-set Gender Intervention Gate runs.

Run from the gender_intervention_gate project root:

    python scripts/summarize_gate_full1588.py

Outputs are written to paper_results/gate_full1588 by default.
The script uses only the Python standard library.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ModelSpec:
    order: int
    display_name: str
    pattern: str


MODEL_SPECS = [
    ModelSpec(1, "OpenAI API", "*_openai_gate_full1588"),
    ModelSpec(2, "Gemini API", "*_gemini_gate_full1588"),
    ModelSpec(3, "Qwen API", "*_qwen_api_gate_full1588"),
    ModelSpec(4, "GLM API", "*_glm_api_gate_full1588"),
    ModelSpec(5, "Qwen 3.5 9B", "*_qwen3_5_9b_ollama_gate_full1588_nothink"),
    ModelSpec(6, "GLM4 9B", "*_glm4_9b_ollama_gate_full1588_nothink"),
    ModelSpec(7, "Gemma2 9B", "*_gemma2_9b_ollama_gate_full1588_nothink"),
    ModelSpec(8, "Llama 3.1 8B", "*_llama3_1_8b_ollama_gate_full1588_native_schema"),
    ModelSpec(9, "Mistral 7B", "*_mistral_7b_ollama_gate_full1588_nothink"),
    ModelSpec(10, "DeepSeek V4 Pro", "*_deepseek_v4_pro_gate_full1588"),
    ModelSpec(11, "DeepSeek-R1 8B", "*_deepseek_r1_8b_ollama_gate_full1588_native_nothink_plain"),
]


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise ValueError(f"Invalid JSON in {path} line {line_no}: {exc}") from exc
    return rows


def percentile(values: list[float], q: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    index = (len(ordered) - 1) * q
    low = math.floor(index)
    high = math.ceil(index)
    if low == high:
        return ordered[low]
    fraction = index - low
    return ordered[low] * (1.0 - fraction) + ordered[high] * fraction


def pct(value: Any) -> str:
    try:
        return f"{float(value) * 100:.2f}%"
    except (TypeError, ValueError):
        return "n/a"


def decimal(value: Any, digits: int = 4) -> str:
    try:
        return f"{float(value):.{digits}f}"
    except (TypeError, ValueError):
        return ""


def validate_candidate(run_dir: Path, expected_count: int) -> tuple[bool, str, dict[str, Any] | None]:
    required = ["metrics.json", "manifest.json", "predictions.jsonl"]
    missing = [name for name in required if not (run_dir / name).is_file()]
    if missing:
        return False, f"missing: {', '.join(missing)}", None

    try:
        metrics = read_json(run_dir / "metrics.json")
        manifest = read_json(run_dir / "manifest.json")
        predictions = read_jsonl(run_dir / "predictions.jsonl")
    except Exception as exc:  # noqa: BLE001 - report malformed run cleanly
        return False, f"read error: {exc}", None

    metric_count = int(metrics.get("count", -1))
    manifest_count = int(manifest.get("count", -1))
    prediction_count = len(predictions)
    if metric_count != expected_count:
        return False, f"metrics count={metric_count}, expected={expected_count}", None
    if manifest_count != expected_count:
        return False, f"manifest count={manifest_count}, expected={expected_count}", None
    if prediction_count != expected_count:
        return False, f"prediction lines={prediction_count}, expected={expected_count}", None

    ids = [str(row.get("id", "")) for row in predictions]
    if len(set(ids)) != expected_count:
        return False, f"unique ids={len(set(ids))}, expected={expected_count}", None

    return True, "complete", {
        "metrics": metrics,
        "manifest": manifest,
        "predictions": predictions,
    }


def select_runs(
    runs_root: Path,
    expected_count: int,
) -> tuple[list[tuple[ModelSpec, Path, dict[str, Any]]], list[dict[str, Any]]]:
    selected: list[tuple[ModelSpec, Path, dict[str, Any]]] = []
    audit: list[dict[str, Any]] = []

    for spec in MODEL_SPECS:
        candidates = sorted(
            [path for path in runs_root.glob(spec.pattern) if path.is_dir()],
            key=lambda path: path.name,
            reverse=True,
        )
        if not candidates:
            raise FileNotFoundError(
                f"No run directory found for {spec.display_name}: {runs_root / spec.pattern}"
            )

        valid_candidates: list[tuple[Path, dict[str, Any], float]] = []
        for candidate in candidates:
            valid, reason, payload = validate_candidate(candidate, expected_count)
            cache_hit_rate = 1.0
            if valid and payload is not None:
                llm_rows = [
                    row for row in payload["predictions"]
                    if str(row.get("route") or "LLM") == "LLM"
                ]
                cache_hits = sum(bool(row.get("cache_hit")) for row in llm_rows)
                cache_hit_rate = (cache_hits / len(llm_rows)) if llm_rows else 0.0
                valid_candidates.append((candidate, payload, cache_hit_rate))
            audit.append(
                {
                    "model_order": spec.order,
                    "display_name": spec.display_name,
                    "run_dir": str(candidate),
                    "valid": valid,
                    "reason": reason,
                    "llm_cache_hit_rate": cache_hit_rate if valid else "",
                    "selected": False,
                }
            )

        if not valid_candidates:
            details = "; ".join(
                f"{row['run_dir']}: {row['reason']}"
                for row in audit
                if row["display_name"] == spec.display_name
            )
            raise RuntimeError(f"No complete run found for {spec.display_name}. {details}")

        # Prefer a fresh/non-cached complete run. If cache-hit rates tie,
        # choose the latest directory name. This prevents a later cache-only
        # duplicate from replacing the original run in latency reporting.
        valid_candidates.sort(key=lambda item: (item[2], item[0].name), reverse=False)
        lowest_cache_rate = valid_candidates[0][2]
        fresh_group = [item for item in valid_candidates if item[2] == lowest_cache_rate]
        chosen_path, chosen_payload, _ = max(fresh_group, key=lambda item: item[0].name)
        for row in audit:
            if row["display_name"] == spec.display_name and row["run_dir"] == str(chosen_path):
                row["selected"] = True
                break
        selected.append((spec, chosen_path, chosen_payload))

    return selected, audit


def summarize_run(spec: ModelSpec, run_dir: Path, payload: dict[str, Any]) -> dict[str, Any]:
    metrics = payload["metrics"]
    manifest = payload["manifest"]
    predictions = payload["predictions"]
    routing = metrics.get("routing") or {}
    confusion = metrics.get("confusion") or {}

    llm_rows = [row for row in predictions if str(row.get("route") or "LLM") == "LLM"]
    non_cached_llm = [row for row in llm_rows if not bool(row.get("cache_hit"))]
    latency_ms = [float(row.get("latency_ms") or 0.0) for row in non_cached_llm]
    cache_hits = sum(bool(row.get("cache_hit")) for row in llm_rows)

    return {
        "order": spec.order,
        "model": spec.display_name,
        "model_key": manifest.get("model_key", ""),
        "model_id": manifest.get("model", ""),
        "run_dir": str(run_dir),
        "count": int(metrics.get("count", 0)),
        "true_positive": int(confusion.get("true_positive", 0)),
        "false_negative": int(confusion.get("false_negative", 0)),
        "true_negative": int(confusion.get("true_negative", 0)),
        "false_positive": int(confusion.get("false_positive", 0)),
        "positive_recall": float(metrics.get("positive_recall", 0.0)),
        "negative_recall": float(metrics.get("negative_recall", 0.0)),
        "balanced_accuracy": float(metrics.get("balanced_accuracy", 0.0)),
        "macro_f1": float(metrics.get("macro_f1", 0.0)),
        "accuracy": float(metrics.get("accuracy", 0.0)),
        "positive_precision": float(metrics.get("positive_precision", 0.0)),
        "negative_precision": float(metrics.get("negative_precision", 0.0)),
        "format_error_rate": float(metrics.get("format_error_rate", 0.0)),
        "passes_90_target": bool(metrics.get("passes_90_target", False)),
        "passes_94_dev_target": bool(metrics.get("passes_94_dev_target", False)),
        "rule_routed": int(routing.get("rule_routed", 0)),
        "llm_routed": int(routing.get("llm_routed", 0)),
        "rule_coverage": float(routing.get("rule_coverage", 0.0)),
        "llm_call_rate": float(routing.get("llm_call_rate", 0.0)),
        "rule_observed_accuracy": routing.get("rule_observed_accuracy"),
        "llm_cache_hits": cache_hits,
        "llm_cache_hit_rate": (cache_hits / len(llm_rows)) if llm_rows else 0.0,
        "mean_llm_latency_ms_non_cached": statistics.mean(latency_ms) if latency_ms else 0.0,
        "median_llm_latency_ms_non_cached": statistics.median(latency_ms) if latency_ms else 0.0,
        "p95_llm_latency_ms_non_cached": percentile(latency_ms, 0.95),
        "sum_llm_latency_seconds_non_cached": sum(latency_ms) / 1000.0,
        "dataset_sha256": manifest.get("dataset_sha256", ""),
        "split_sha256": manifest.get("split_sha256", ""),
        "prompt_sha256": manifest.get("prompt_sha256", ""),
        "examples_sha256": manifest.get("examples_sha256", ""),
        "rules_sha256": (manifest.get("rule_first") or {}).get("rules_sha256", ""),
    }


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fields = list(rows[0].keys())
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def write_markdown(path: Path, rows: list[dict[str, Any]]) -> None:
    lines = [
        "# Full-set Gender Intervention Gate Results",
        "",
        "Selection rule: for duplicate run names, prefer the complete run with the lowest LLM cache-hit rate; break ties by choosing the latest run.",
        "",
        "| Model | Pos. Recall | Neg. Recall | Balanced Acc. | Macro-F1 | Accuracy | Rule Cov. | Format Err. | Pass 90% |",
        "|---|---:|---:|---:|---:|---:|---:|---:|:---:|",
    ]
    for row in rows:
        lines.append(
            "| {model} | {pr} | {nr} | {ba} | {mf1} | {acc} | {rc} | {fe} | {pass90} |".format(
                model=row["model"],
                pr=pct(row["positive_recall"]),
                nr=pct(row["negative_recall"]),
                ba=pct(row["balanced_accuracy"]),
                mf1=pct(row["macro_f1"]),
                acc=pct(row["accuracy"]),
                rc=pct(row["rule_coverage"]),
                fe=pct(row["format_error_rate"]),
                pass90="Yes" if row["passes_90_target"] else "No",
            )
        )

    lines.extend(
        [
            "",
            "## Selected runs",
            "",
            "| Model | Model ID | Run directory |",
            "|---|---|---|",
        ]
    )
    for row in rows:
        lines.append(f"| {row['model']} | `{row['model_id']}` | `{row['run_dir']}` |")

    lines.extend(
        [
            "",
            "## Latency and cache diagnostics",
            "",
            "Latency is calculated only from non-cached LLM-routed predictions. Summed latency is not wall-clock runtime when concurrency is greater than one.",
            "",
            "| Model | LLM calls | Cache hits | Cache-hit rate | Mean latency | Median latency | P95 latency |",
            "|---|---:|---:|---:|---:|---:|---:|",
        ]
    )
    for row in rows:
        lines.append(
            f"| {row['model']} | {row['llm_routed']} | {row['llm_cache_hits']} | "
            f"{pct(row['llm_cache_hit_rate'])} | "
            f"{row['mean_llm_latency_ms_non_cached'] / 1000:.2f}s | "
            f"{row['median_llm_latency_ms_non_cached'] / 1000:.2f}s | "
            f"{row['p95_llm_latency_ms_non_cached'] / 1000:.2f}s |"
        )

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_acl_table(path: Path, rows: list[dict[str, Any]]) -> None:
    lines = [
        "% Auto-generated by summarize_gate_full1588.py",
        "\\begin{table*}[t]",
        "\\centering",
        "\\small",
        "\\begin{tabular}{lrrrrrr}",
        "\\toprule",
        "Model & Pos. Rec. & Neg. Rec. & Bal. Acc. & Macro-F1 & Rule Cov. & Fmt. Err. \\\\",
        "\\midrule",
    ]
    for row in rows:
        model = str(row["model"]).replace("_", "\\_")
        lines.append(
            f"{model} & {row['positive_recall'] * 100:.2f} & "
            f"{row['negative_recall'] * 100:.2f} & "
            f"{row['balanced_accuracy'] * 100:.2f} & "
            f"{row['macro_f1'] * 100:.2f} & "
            f"{row['rule_coverage'] * 100:.2f} & "
            f"{row['format_error_rate'] * 100:.2f} \\\\"
        )
    lines.extend(
        [
            "\\bottomrule",
            "\\end{tabular}",
            "\\caption{Full-set performance of the rule-first gender intervention gate. All values except model names are percentages.}",
            "\\label{tab:gate-full-results}",
            "\\end{table*}",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs-root", default="runs", help="Directory containing run folders")
    parser.add_argument(
        "--output-dir",
        default="paper_results/gate_full1588",
        help="Directory for generated reports",
    )
    parser.add_argument("--expected-count", type=int, default=1588)
    args = parser.parse_args()

    runs_root = Path(args.runs_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    selected, audit = select_runs(runs_root, args.expected_count)
    rows = [summarize_run(spec, run_dir, payload) for spec, run_dir, payload in selected]
    rows.sort(key=lambda row: int(row["order"]))

    write_csv(output_dir / "gate_all_models.csv", rows)
    write_csv(output_dir / "duplicate_runs_audit.csv", audit)
    write_markdown(output_dir / "gate_all_models.md", rows)
    write_acl_table(output_dir / "acl_table_gate.tex", rows)
    (output_dir / "gate_all_models.json").write_text(
        json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print("Selected complete runs:")
    for row in rows:
        print(f"  {row['order']:>2}. {row['model']:<20} -> {row['run_dir']}")
    print()
    duplicate_models = {
        row["display_name"]
        for row in audit
        if sum(1 for item in audit if item["display_name"] == row["display_name"]) > 1
    }
    if duplicate_models:
        print("Duplicate run groups detected:")
        for name in sorted(duplicate_models):
            selected_path = next(
                item["run_dir"]
                for item in audit
                if item["display_name"] == name and item["selected"]
            )
            print(f"  {name}: selected preferred complete run {selected_path}")
        print(f"  Audit: {output_dir / 'duplicate_runs_audit.csv'}")
        print()

    print("Generated reports:")
    for name in [
        "gate_all_models.csv",
        "gate_all_models.json",
        "gate_all_models.md",
        "duplicate_runs_audit.csv",
        "acl_table_gate.tex",
    ]:
        print(f"  {output_dir / name}")


if __name__ == "__main__":
    main()
