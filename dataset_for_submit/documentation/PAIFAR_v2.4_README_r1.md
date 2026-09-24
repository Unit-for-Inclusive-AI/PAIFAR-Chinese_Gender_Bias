# PAIFAR Benchmark v2.4

## Overview

PAIFAR Benchmark is a Chinese benchmark for evaluating **intervention calibration** in gender-inclusive language generation. It is designed to test whether language models can determine **when gender-related content should be preserved** and **when a gender-inclusive rewrite is required**.

The benchmark contains two complementary subsets:

- **Golden Negative**: preservation-required cases in which gender-related information should remain unchanged. These examples are used to measure unnecessary intervention and overcorrection.
- **Golden Positive**: intervention-required cases in which a gender-inclusive rewrite is appropriate. These examples are used to evaluate bias mitigation, semantic preservation, and rewrite quality.

All model inputs, reference outputs, and instance-level rationales are in Chinese. English taxonomy labels are included to improve accessibility for non-Chinese-speaking researchers.

> English translations shown in the associated paper are provided only for readability. They are not used as model inputs, reference outputs, or evaluation targets.

---

## Dataset Statistics

| Subset | Samples | Gold Label | L1 Categories | L2 Categories |
|---|---:|---|---:|---:|
| Golden Negative | 717 | `KEEP` | 8 | 50 |
| Golden Positive | 871 | `EDIT` | 7 | 41 |
| **Total** | **1,588** | — | **15** | **91** |

### Task Definition

Given a Chinese input text \(x\), a system predicts an intervention decision:

- `KEEP`: preserve the original text because the gender-related expression serves a necessary factual, referential, identity-related, discourse, pragmatic, institutional, medical, or lexical function.
- `EDIT`: rewrite the text because the gendered expression introduces an unnecessary default, stereotype, asymmetry, restriction, derogation, or other form of exclusionary language.

The benchmark supports two related evaluation settings:

1. **Intervention decision**: determine whether the input should be kept or edited.
2. **Selective rewriting**: when the decision is `EDIT`, generate a gender-inclusive rewrite while preserving the original meaning, factual content, register, and required information.

---

## Repository Structure

```text
PAIFAR_Benchmark_v2.4/
├── README.md
├── data/
│   ├── golden_negative_v2.4_core.csv
│   └── golden_positive_v2.4_core.csv
├── taxonomy/
│   ├── taxonomy_negative_v2.4.csv
│   └── taxonomy_positive_v2.4.csv
└── documentation/
    ├── data_dictionary_core.csv
    └── value_mapping_core.csv
```

The public core CSV files contain the fields needed to inspect and evaluate the benchmark. Internal data-management fields are excluded from the core release.

---

## Files

### `data/golden_negative_v2.4_core.csv`

Contains 717 preservation-required examples. All rows have:

```text
gold_label = KEEP
```

Core annotation fields include:

- Chinese input and preserved reference output
- bilingual L1 and L2 taxonomy labels
- trigger span
- preservation rationale
- a typical overcorrection
- broad register category
- noise type
- difficulty

### `data/golden_positive_v2.4_core.csv`

Contains 871 intervention-required examples. All rows have:

```text
gold_label = EDIT
```

Core annotation fields include:

- Chinese input and reference rewrite
- bilingual L1 and L2 taxonomy labels
- trigger span
- intervention rationale
- acceptable alternative rewrites
- typical under-editing and over-editing errors
- information that must be preserved
- broad register category
- noise type
- difficulty

### `taxonomy/`

The taxonomy files define stable category identifiers and bilingual category names.

- Negative categories use identifiers such as `N1` and `N1.1`.
- Positive categories use identifiers such as `P1` and `P1.1`.

Each taxonomy file also reports:

- sample count
- share of the full subset
- share within the corresponding L1 category

### `documentation/data_dictionary_core.csv`

Provides the type, language, description, and allowed values for every field in the core release.

### `documentation/value_mapping_core.csv`

Maps original Chinese categorical values to the English codes used in the public release.

---

## Core Fields

### Shared Fields

| Field | Description |
|---|---|
| `id` | Unique sample identifier |
| `l1_id` | Top-level taxonomy identifier |
| `l1_category_zh` | Chinese L1 category name |
| `l1_category_en` | English L1 category name |
| `l2_id` | Second-level taxonomy identifier |
| `l2_category_zh` | Chinese L2 category name |
| `l2_category_en` | English L2 category name |
| `register_category_zh` | Broad Chinese register/domain category |
| `register_category_en` | English register/domain category |
| `noise_type` | English code for intentionally preserved surface noise |
| `input_zh` | Original Chinese input |
| `reference_output_zh` | Preserved text or reference rewrite |
| `gold_label` | `KEEP` or `EDIT` |
| `trigger_span_zh` | Gender-related or apparent trigger span |
| `difficulty` | `easy`, `medium`, or `hard` |

### Golden Negative–Specific Fields

| Field | Description |
|---|---|
| `preservation_rationale_zh` | Why the gender-related expression must be preserved |
| `common_overcorrection_zh` | A typical unnecessary or harmful modification |

### Golden Positive–Specific Fields

| Field | Description |
|---|---|
| `intervention_rationale_zh` | Why a gender-inclusive intervention is required |
| `acceptable_alternatives_zh` | Other acceptable rewrites |
| `under_editing_trap_zh` | A typical incomplete rewrite |
| `over_editing_trap_zh` | A typical excessive rewrite |
| `required_information_zh` | Information that must remain unchanged |

---

## Loading the Data

### Python

```python
import pandas as pd

negative = pd.read_csv(
    "data/golden_negative_v2.4_core.csv",
    encoding="utf-8-sig",
)

positive = pd.read_csv(
    "data/golden_positive_v2.4_core.csv",
    encoding="utf-8-sig",
)

print(negative.shape)  # (717, 17)
print(positive.shape)  # (871, 20)

assert set(negative["gold_label"]) == {"KEEP"}
assert set(positive["gold_label"]) == {"EDIT"}
```

### Combined Decision Dataset

For intervention-decision experiments, the two subsets can be combined using their shared fields:

```python
shared_fields = [
    "id",
    "l1_id",
    "l1_category_zh",
    "l1_category_en",
    "l2_id",
    "l2_category_zh",
    "l2_category_en",
    "register_category_zh",
    "register_category_en",
    "noise_type",
    "input_zh",
    "reference_output_zh",
    "gold_label",
    "trigger_span_zh",
    "difficulty",
]

decision_data = pd.concat(
    [
        negative[shared_fields],
        positive[shared_fields],
    ],
    ignore_index=True,
)

print(decision_data.shape)  # (1588, 15)
```

---

## Recommended Evaluation

### Intervention Decision

Recommended metrics include:

- accuracy
- balanced accuracy
- `KEEP` recall
- `EDIT` recall
- overcorrection rate on Golden Negative
- missed-intervention rate on Golden Positive

Because the two subsets serve different diagnostic purposes, results should be reported separately as well as jointly.

### Rewriting

For Golden Positive, rewriting should be assessed along multiple dimensions:

- bias mitigation
- semantic and factual preservation
- relevance to the identified problem
- naturalness and fluency
- preservation of register and required information

A rewrite should not receive full credit merely for removing a gender-related expression. It must also preserve the meaning and communicative function of the original text.

---

## Language and Annotation Notes

- All benchmark instances are Chinese.
- English labels are metadata for accessibility and do not replace the Chinese annotations.
- Chinese allows subject and pronoun omission, which is often relevant to gender-inclusive rewriting.
- Some gender-related expressions are factually, institutionally, medically, referentially, or lexically necessary.
- Some apparent gender triggers are false positives whose surface forms do not express human gender.
- Noise and informal language are intentionally retained in selected examples to test robustness.

---

## Intended Uses

The benchmark is intended for:

- evaluation of gender-inclusive Chinese generation
- intervention calibration and selective rewriting
- overcorrection analysis
- semantic-preservation evaluation
- prompt, verifier, and rewriting-system analysis
- research on context-sensitive bias mitigation

---

## Out-of-Scope Uses

The benchmark should not be used as:

- a universal definition of gender-inclusive Chinese
- a substitute for consultation with affected communities
- a tool for inferring the gender identity of individuals
- an automatic moderation policy without human oversight
- a benchmark for languages other than Chinese without adaptation

---

## Limitations

- The benchmark focuses on Chinese and reflects Chinese linguistic and cultural contexts.
- The taxonomy is designed for gender-inclusive generation and does not cover every form of social bias.
- Some cases may admit multiple reasonable rewrites.
- Instance-level rationales are written in Chinese and may require Chinese proficiency.
- The benchmark evaluates sentence- or short-text-level inputs and may not fully capture document-level discourse.
- Category distributions are intentionally broad rather than naturally occurring corpus frequencies.

---

## Versioning

This release is:

```text
PAIFAR Benchmark v2.4
```

Future releases should document:

- added, removed, or revised samples
- taxonomy changes
- annotation corrections
- field-schema changes
- compatibility with earlier versions

---

## Citation

Citation information will be added after the associated paper is publicly available.

For anonymous review, do not add author-identifying repository links, names, institutional affiliations, or non-anonymous citation records.

---

## License

The final license should be confirmed before public release. The selected license must be compatible with the source data, annotation process, and intended research use.

---

## Contact

Contact information will be added after the anonymous review period.
