#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any

MODEL_NAMES = {
    "openai": "GPT-4o",
    "gemini": "Gemini",
    "qwen_api": "Qwen API",
    "glm_api": "GLM API",
    "qwen3_5_9b_ollama": "Qwen3.5-9B",
    "glm4_9b_ollama": "GLM4-9B",
    "gemma2_9b_ollama": "Gemma2-9B",
    "llama3_1_8b_ollama": "Llama3.1-8B",
    "mistral_7b_ollama": "Mistral-7B",
    "deepseek_v4_pro": "DeepSeek-V4-Pro",
    "deepseek_r1_8b_ollama": "DeepSeek-R1-8B",
}

MODEL_GROUPS = {
    "openai": "API",
    "gemini": "API",
    "qwen_api": "API",
    "glm_api": "API",
    "deepseek_v4_pro": "API",
    "qwen3_5_9b_ollama": "Local",
    "glm4_9b_ollama": "Local",
    "gemma2_9b_ollama": "Local",
    "llama3_1_8b_ollama": "Local",
    "mistral_7b_ollama": "Local",
    "deepseek_r1_8b_ollama": "Local",
}


def latest_index(root: Path) -> Path:
    candidates = sorted(
        root.glob("logs/judge_positive_full871/direct_zero_shot/*/run_index.tsv"),
        key=lambda p: p.parent.name,
        reverse=True,
    )
    if not candidates:
        raise FileNotFoundError(
            "No Direct Judge run_index.tsv found under "
            "logs/judge_positive_full871/direct_zero_shot/"
        )
    return candidates[0]


def load_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    if not rows:
        raise ValueError(f"Empty index: {path}")
    return rows


def resolve_project_path(root: Path, value: str) -> Path:
    path = Path(value).expanduser()
    return path if path.is_absolute() else root / path


def metric(section: dict[str, Any] | None, key: str) -> Any:
    return None if not section else section.get(key)


def fmt_num(value: Any, digits: int = 2) -> str:
    if value is None or value == "":
        return "—"
    return f"{float(value):.{digits}f}"


def fmt_rate(value: Any) -> str:
    if value is None or value == "":
        return "—"
    return f"{float(value) * 100:.2f}%"


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        raise ValueError("No summary rows to write")
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Aggregate Direct Zero-shot Frozen Judge v04 results."
    )
    parser.add_argument(
        "--index",
        help=(
            "Direct Judge run_index.tsv. When omitted, the latest index under "
            "logs/judge_positive_full871/direct_zero_shot/ is used."
        ),
    )
    parser.add_argument(
        "--output-dir",
        default="paper_results/positive_full871/direct_zero_shot",
    )
    args = parser.parse_args()

    root = Path.cwd().resolve()
    index_path = (
        resolve_project_path(root, args.index)
        if args.index
        else latest_index(root)
    )
    output_dir = resolve_project_path(root, args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    detailed_rows: list[dict[str, Any]] = []
    warnings: list[str] = []

    for index_row in load_tsv(index_path):
        alias = index_row.get("model_alias", "").strip()
        status = index_row.get("judge_status", "").strip()
        order_text = index_row.get("order", "").strip()
        order = int(order_text) if order_text.isdigit() else 999
        scored_n_text = index_row.get("scored_n", "").strip()
        writer_failures_text = index_row.get("writer_failures", "").strip()
        scored_n = int(scored_n_text) if scored_n_text.isdigit() else None
        writer_failures = (
            int(writer_failures_text) if writer_failures_text.isdigit() else None
        )

        judge_run_text = index_row.get("judge_run", "").strip()
        judge_run: Path | None = None
        metrics: dict[str, Any] | None = None

        if judge_run_text and judge_run_text != "-":
            judge_run = resolve_project_path(root, judge_run_text)
            metrics_path = judge_run / "metrics.json"
            if metrics_path.exists():
                metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
            else:
                warnings.append(f"Missing metrics.json: {metrics_path}")
        else:
            warnings.append(f"No Judge run recorded for {alias or order_text}")

        overall = metrics.get("overall", {}) if metrics else {}
        local = metrics.get("local_repair", {}) if metrics else {}
        reconstruction = (
            metrics.get("proposition_reconstruction", {}) if metrics else {}
        )

        metrics_count = metric(overall, "count")
        if scored_n is not None and metrics_count is not None:
            if int(metrics_count) != scored_n:
                warnings.append(
                    f"Count mismatch for {alias}: index scored_n={scored_n}, "
                    f"metrics count={metrics_count}"
                )

        detailed_rows.append(
            {
                "order": order,
                "model_alias": alias,
                "model": MODEL_NAMES.get(alias, alias),
                "group": MODEL_GROUPS.get(alias, "Unknown"),
                "method": "Direct Zero-shot",
                "writer_input_n": (
                    scored_n + writer_failures
                    if scored_n is not None and writer_failures is not None
                    else None
                ),
                "scored_n": scored_n,
                "writer_failure_n": writer_failures,
                "judge_valid_n": metric(overall, "valid_count"),
                "judge_error_n": metric(overall, "error_count"),
                "overall_quality": metric(overall, "quality_score"),
                "macro_quality": metrics.get("macro_quality_score") if metrics else None,
                "debiasing": metric(overall, "debiasing_score"),
                "naturalness": metric(overall, "naturalness_score"),
                "fidelity_or_relevance": metric(overall, "type_specific_score"),
                "local_repair_quality": metric(local, "quality_score"),
                "proposition_reconstruction_quality": metric(
                    reconstruction, "quality_score"
                ),
                "pass_rate": metric(overall, "pass_rate"),
                "partial_rate": metric(overall, "partial_rate"),
                "fail_rate": metric(overall, "fail_rate"),
                "local_repair_n": metric(local, "count"),
                "proposition_reconstruction_n": metric(reconstruction, "count"),
                "judge_status": status,
                "writer_run": index_row.get("writer_run", ""),
                "judge_run": str(judge_run) if judge_run else "",
            }
        )

    detailed_rows.sort(key=lambda r: int(r["order"]))

    detailed_csv = output_dir / "direct_zero_shot_judge_detailed.csv"
    write_csv(detailed_csv, detailed_rows)

    acl_rows: list[dict[str, Any]] = []
    for r in detailed_rows:
        acl_rows.append(
            {
                "Model": r["model"],
                "Group": r["group"],
                "N": r["scored_n"],
                "Generation Failures": r["writer_failure_n"],
                "Overall": r["overall_quality"],
                "Macro": r["macro_quality"],
                "Debiasing": r["debiasing"],
                "Naturalness": r["naturalness"],
                "Fidelity/Relevance": r["fidelity_or_relevance"],
                "Local Repair": r["local_repair_quality"],
                "Reconstruction": r["proposition_reconstruction_quality"],
                "Pass Rate": r["pass_rate"],
            }
        )

    acl_csv = output_dir / "direct_zero_shot_judge_acl_table.csv"
    write_csv(acl_csv, acl_rows)

    lines = [
        "# Direct Zero-shot — Frozen Judge v04 Summary",
        "",
        f"Source index: `{index_path}`",
        "",
        "| Model | Group | N | Gen. fail | Overall | Macro | Debiasing | Naturalness | Fidelity/Relevance | Local | Reconstruction | PASS |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in detailed_rows:
        lines.append(
            "| {model} | {group} | {n} | {gen_fail} | {overall} | {macro} | "
            "{debiasing} | {naturalness} | {type_specific} | {local} | {recon} | {pass_rate} |".format(
                model=r["model"],
                group=r["group"],
                n=r["scored_n"] if r["scored_n"] is not None else "—",
                gen_fail=(
                    r["writer_failure_n"]
                    if r["writer_failure_n"] is not None
                    else "—"
                ),
                overall=fmt_num(r["overall_quality"]),
                macro=fmt_num(r["macro_quality"]),
                debiasing=fmt_num(r["debiasing"]),
                naturalness=fmt_num(r["naturalness"]),
                type_specific=fmt_num(r["fidelity_or_relevance"]),
                local=fmt_num(r["local_repair_quality"]),
                recon=fmt_num(r["proposition_reconstruction_quality"]),
                pass_rate=fmt_rate(r["pass_rate"]),
            )
        )

    lines.extend(
        [
            "",
            "Scoring weights: Debiasing 50%, Naturalness 25%, and the type-specific fidelity/relevance metric 25%.",
            "Generation failures were excluded before Judge scoring and are reported separately.",
        ]
    )
    md_path = output_dir / "direct_zero_shot_judge_summary.md"
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    json_path = output_dir / "direct_zero_shot_judge_detailed.json"
    json_path.write_text(
        json.dumps(detailed_rows, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print("\n".join(lines))
    print("\nOutputs:")
    print(f"  Detailed CSV: {detailed_csv}")
    print(f"  ACL CSV:      {acl_csv}")
    print(f"  Markdown:     {md_path}")
    print(f"  JSON:         {json_path}")
    if warnings:
        print("\nWarnings:")
        for warning in warnings:
            print(f"  - {warning}")


if __name__ == "__main__":
    main()
