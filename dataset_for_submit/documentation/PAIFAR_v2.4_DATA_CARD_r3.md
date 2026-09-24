# PAIFAR Benchmark v2.4 — Data Card

## 1. Dataset Summary

PAIFAR Benchmark is a Chinese benchmark for evaluating **intervention calibration** in gender-inclusive language generation. It measures whether a model can distinguish between:

- gender-related content that should be **preserved**; and
- gender-related content that should be **rewritten**.

The benchmark contains two complementary subsets:

| Subset | Samples | Gold Label | L1 Categories | L2 Categories |
|---|---:|---|---:|---:|
| Golden Negative | 717 | `KEEP` | 8 | 50 |
| Golden Positive | 871 | `EDIT` | 7 | 41 |
| **Total** | **1,588** | — | **15** | **91** |

All inputs, reference outputs, trigger spans, and instance-level rationales are in Chinese. English taxonomy and register labels are included to improve accessibility.

> English translations used in the associated paper are provided only for readability. They are not used as model inputs, gold outputs, or evaluation targets.

---

## 2. Motivation

Research on gender-inclusive generation often focuses on whether models can remove or reduce gender bias when intervention is needed. Less attention has been paid to whether models intervene **unnecessarily** when gender-related content serves a valid linguistic or factual function.

PAIFAR Benchmark was designed to support evaluation of both sides of the decision:

1. **Under-intervention**: failing to rewrite genuinely biased or exclusionary language.
2. **Over-intervention**: rewriting gender-related content that should remain unchanged.

This distinction is especially important in Chinese, where gender-related expressions may be referentially necessary, factually required, institutionally fixed, medically relevant, quoted, self-identified, lexicalized, or only superficially similar to human-gender expressions.

---

## 3. Task Definition

Given a Chinese input text \(x\), a system predicts an intervention decision:

- `KEEP`: preserve the original text.
- `EDIT`: produce a gender-inclusive rewrite.

A `KEEP` decision is appropriate when the relevant expression performs a necessary function, including factual, referential, identity-related, discourse, pragmatic, institutional, medical, historical, or lexical functions.

An `EDIT` decision is appropriate when the expression introduces an unnecessary gender default, stereotype, asymmetry, prescription, restriction, derogation, objectification, or other exclusionary framing.

The benchmark supports:

- intervention-decision evaluation;
- selective rewriting;
- overcorrection analysis;
- semantic-preservation analysis;
- verifier and refinement evaluation.

---

## 4. Dataset Composition

### 4.1 Golden Negative

Golden Negative contains 717 preservation-required examples. Every sample has:

```text
gold_label = KEEP
```

Its taxonomy covers cases such as:

- reference to specific individuals of known gender;
- biologically or medically necessary gender information;
- institutionally or statistically necessary distinctions;
- proper names and fixed designations;
- quotations and reported speech;
- self-identification and self-reference;
- lexicalized or historically conventional forms;
- false gender triggers.

Core fields include the original input, preserved reference output, trigger span, preservation rationale, and a representative overcorrection.

### 4.2 Golden Positive

Golden Positive contains 871 intervention-required examples. Every sample has:

```text
gold_label = EDIT
```

Its taxonomy covers cases such as:

- gendered defaults under missing information;
- redundant gender marking;
- gender–attribute associations;
- gendered norms and prescriptions;
- relational asymmetry;
- gender-based restrictions;
- derogation and objectification.

Core fields include the original input, reference rewrite, trigger span, intervention rationale, acceptable alternatives, under-editing and over-editing traps, and information that must be preserved.

---

## 5. Data Fields

The public core files retain fields necessary for direct inspection and benchmark use.

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
| `noise_type` | English code for intentionally retained surface noise |
| `input_zh` | Original Chinese input |
| `reference_output_zh` | Preserved text or reference rewrite |
| `gold_label` | `KEEP` or `EDIT` |
| `trigger_span_zh` | Gender-related or apparent trigger span |
| `difficulty` | `easy`, `medium`, or `hard` |

### Golden Negative–Specific Fields

| Field | Description |
|---|---|
| `preservation_rationale_zh` | Reason the original gender-related content must be preserved |
| `common_overcorrection_zh` | Representative unnecessary or harmful modification |

### Golden Positive–Specific Fields

| Field | Description |
|---|---|
| `intervention_rationale_zh` | Reason intervention is required |
| `acceptable_alternatives_zh` | Other acceptable rewrites |
| `under_editing_trap_zh` | Typical incomplete edit |
| `over_editing_trap_zh` | Typical excessive edit |
| `required_information_zh` | Information that must remain unchanged |

A complete machine-readable description is provided in `documentation/data_dictionary_core.csv`.

---

## 6. Taxonomy

The benchmark uses separate taxonomies for the two subsets because they capture different phenomena:

- the Negative taxonomy describes **functions that protect gender-related content from intervention**;
- the Positive taxonomy describes **phenomena that justify intervention**.

Stable category identifiers are used:

- Negative: `N1`–`N8`, with L2 identifiers such as `N1.1`;
- Positive: `P1`–`P7`, with L2 identifiers such as `P1.1`.

The taxonomy files provide Chinese and English labels, category counts, subset shares, and within-L1 shares.

---

## 7. Register Coverage

### 7.1 Golden Negative

| Value | Count |
|---|---:|
| Academic and Research | 106 |
| Other | 97 |
| Official and Regulatory Text | 86 |
| Normative Baseline Examples | 86 |
| Medical and Health | 57 |
| Engineering and Technology | 57 |
| News Reporting | 55 |
| Spoken and Private Communication | 53 |
| Social and Community | 46 |
| Literary and Cultural Writing | 29 |
| Business and Product | 24 |
| Legal and Judicial | 21 |

### 7.2 Golden Positive

| Value | Count |
|---|---:|
| Other | 414 |
| Social and Community | 94 |
| Official and Regulatory Text | 93 |
| Business and Product | 82 |
| Spoken and Private Communication | 47 |
| Academic and Research | 31 |
| Literary and Cultural Writing | 29 |
| Medical and Health | 29 |
| Engineering and Technology | 23 |
| News Reporting | 20 |
| Legal and Judicial | 9 |

Register distributions reflect benchmark coverage and should not be interpreted as estimates of naturally occurring language frequencies.

---

## 8. Noise and Robustness Features

Selected examples preserve surface variation such as informal language, typographical noise, abbreviations, emoji, ASR-style transcription, OCR-style line errors, irregular spacing, mixed full-width and half-width forms, and Traditional Chinese.

### 8.1 Golden Negative Noise Types

| Value | Count |
|---|---:|
| none | 641 |
| structured_text | 20 |
| abbreviation | 19 |
| dialect | 6 |
| typo | 5 |
| asr_transcription | 5 |
| internet_slang | 5 |
| emoji | 4 |
| pinyin_abbreviation | 3 |
| ocr_line_break | 3 |
| repeated_punctuation | 2 |
| mixed_full_half_width | 2 |
| irregular_spacing | 1 |
| traditional_chinese | 1 |

### 8.2 Golden Positive Noise Types

| Value | Count |
|---|---:|
| none | 733 |
| internet_slang | 41 |
| structured_text | 37 |
| dialect | 15 |
| emoji | 10 |
| abbreviation | 7 |
| missing_punctuation | 7 |
| typo | 6 |
| repeated_punctuation | 5 |
| asr_transcription | 4 |
| mixed_full_half_width | 2 |
| traditional_chinese | 2 |
| pinyin_abbreviation | 2 |

Noise is included to test whether intervention decisions and rewrites remain robust without treating unrelated surface variation as an error to be corrected.

---

## 9. Difficulty Distribution

### 9.1 Golden Negative

| Value | Count |
|---|---:|
| medium | 278 |
| easy | 267 |
| hard | 172 |

### 9.2 Golden Positive

| Value | Count |
|---|---:|
| medium | 537 |
| easy | 307 |
| hard | 27 |

Difficulty labels are human-assigned and should be interpreted as relative diagnostic groupings rather than calibrated psychometric measurements.

---

## 10. Data Construction

The two subsets were constructed through related but distinct processes.

### 10.1 Golden Negative

The Golden Negative taxonomy was developed **inductively from difficult observed examples**. The construction process began with a collection of hard cases in which gender-related expressions might appear, at first glance, to invite inclusive rewriting, but should in fact be preserved when their function is evaluated in context.

These examples were analyzed with attention to multiple linguistic and communicative dimensions, including:

- local and broader context;
- sentence-level and discourse-level meaning;
- pragmatic purpose;
- referential function;
- speaker stance;
- factual content;
- identity-related function;
- institutional, medical, historical, or lexical constraints.

Recurring preservation functions were first grouped into broad L1 categories. Each L1 category was then refined into more specific L2 subcategories. Representative seed examples were written or selected for each category to clarify its scope and decision boundary.

AI-assisted generation was subsequently used to expand the set of candidate examples from these representative seeds. Expansion was constrained by four main criteria:

1. **category validity** — the example had to instantiate the intended preservation function;
2. **realism** — the content had to resemble plausible Chinese usage;
3. **naturalness** — the sentence had to be fluent and appropriate for its register;
4. **diversity** — examples had to vary in wording, domain, register, trigger type, and surface form.

The expanded candidates were then manually reviewed, revised, or removed. Particular attention was paid to whether a gender-related expression was genuinely protected by its contextual, semantic, pragmatic, factual, referential, identity-related, institutional, medical, historical, or lexical function.

The resulting Negative taxonomy therefore reflects an analysis of **why apparently gender-marked content may need to remain unchanged**, rather than a predefined list of conventional bias categories.

### 10.2 Golden Positive

Golden Positive followed a similar seed-and-expansion workflow, but its taxonomy had a different origin. Positive categories were not induced primarily from difficult preservation cases. Instead, they began from a comparatively mature set of gender-bias and gender-inclusive-language phenomena, such as gendered defaults, stereotypes, prescriptive norms, asymmetry, restrictions, derogation, and objectification.

These broad categories were adapted to the Chinese gender-inclusive rewriting setting and refined into L2 subcategories. Representative examples were prepared for each category, after which AI-assisted generation was used to expand the candidate pool.

As with Golden Negative, candidate expansion was guided by:

- correctness with respect to the intended category;
- realism;
- linguistic naturalness;
- diversity of registers, domains, forms, and trigger expressions;
- preservation of the non-gender-related meaning and communicative purpose.

The generated candidates were manually checked and revised to ensure that intervention was genuinely warranted and that the reference rewrite addressed the gender-related problem without introducing unnecessary semantic changes.

### 10.3 Shared Construction Principles

Across both subsets, AI was used as an **assistance mechanism for controlled example expansion**, not as the final authority for taxonomy assignment, gold decisions, or reference quality. Human review determined whether an item was retained in the benchmark.

The shared construction workflow was:

1. identify or define the target phenomenon;
2. establish an L1 category and refine it into L2 subcategories;
3. prepare representative seed examples;
4. generate diverse candidate examples with AI assistance;
5. review candidates for category fit, realism, naturalness, and diversity;
6. assign the gold decision, trigger span, rationale, and reference output;
7. revise or remove unsuitable examples;
8. conduct consistency checks before the v2.4 release.

### Information still requiring final documentation

The following details should be completed from the final project records:

- **Source provenance:** `[TODO: specify the types of observed examples used during initial analysis and whether any released sentence is directly adapted from an external source.]`
- **AI assistance:** `[TODO: record the model(s), prompting procedure, and approximate stage or proportion of AI-assisted candidate expansion.]`
- **Personal-data screening:** `[TODO: describe procedures for avoiding or removing identifiable personal information.]`
- **Deduplication:** `[TODO: document exact duplicate and near-duplicate checks.]`
- **Version history:** `[TODO: summarize the main changes leading to v2.4.]`

---
## 11. Annotation Process

Two Chinese-speaking annotators participated in dataset construction and quality control. The primary annotator developed the taxonomy, performed the initial instance-level annotation, revised candidate examples, and finalized the released annotations. These annotations include the `KEEP/EDIT` decision, L1 and L2 category assignments, trigger spans, reference outputs, and subset-specific rationales and error descriptions.

The second annotator reviewed a subset of the data during quality control and independently re-annotated the core intervention decision for a stratified sample of 300 blinded instances, comprising 150 Golden Negative and 150 Golden Positive examples. The second annotator did not have access to the original decision labels during this reliability check.

The two annotators achieved 89.67% raw agreement on the `KEEP/EDIT` decision, with a Cohen's kappa of 0.793. Because the primary annotator designed the taxonomy and reviewed the full dataset, the primary annotator served as the final adjudicator for the released labels. Disagreements from the reliability sample were retained as diagnostic evidence and did not automatically overwrite the primary annotations.

L1/L2 category assignments and other structured fields were produced by the primary annotator and spot-checked by the second annotator. No formal inter-annotator agreement score was computed for these auxiliary fields.

### Annotation dimensions

- intervention decision;
- L1 and L2 category;
- trigger span;
- reference output;
- broad register;
- noise type;
- difficulty;
- subset-specific rationale and error annotations.

---

## 12. Quality Control

All AI-generated candidates were manually reviewed before inclusion. Candidate instances were checked for:

- consistency with the intended L1 and L2 category;
- validity of the `KEEP` or `EDIT` decision;
- sufficient sentence-level evidence for the decision;
- semantic clarity and logical coherence;
- linguistic naturalness and real-world plausibility;
- reference-output quality and preservation of necessary information;
- diversity across domains, registers, sentence structures, and trigger forms;
- excessive duplication, templatic repetition, or visible generation artifacts.

Candidates that were largely valid but contained wording or annotation problems were manually revised. Instances with unclear category boundaries, insufficient decision evidence, unnatural language, logical inconsistencies, excessive similarity to existing examples, or limited diagnostic value were removed.

Release-level consistency checks include:

- 717 unique Golden Negative IDs;
- 871 unique Golden Positive IDs;
- 1,588 unique samples in total;
- all Golden Negative labels equal `KEEP`;
- all Golden Positive labels equal `EDIT`;
- Negative L2 category counts sum to 717;
- Positive L2 category counts sum to 871;
- taxonomy identifiers and bilingual labels are consistent across files;
- public CSV fields match the accompanying data dictionary;
- internal data-management fields are excluded from the core release.

The 300-instance blind re-annotation study provides an additional reliability check for the benchmark's core intervention decision.

Additional items still requiring documentation before public release are:

- `[TODO: harmful-content and privacy screening procedure]`
- `[TODO: exact duplicate and near-duplicate detection procedure]`

---
## 13. Recommended Uses

PAIFAR Benchmark is intended for:

- evaluating intervention calibration;
- measuring overcorrection in gender-inclusive generation;
- evaluating Chinese selective rewriting;
- testing semantic-preservation mechanisms;
- analyzing prompt, verifier, and refinement strategies;
- comparing model families and scales;
- studying robustness across registers and surface noise.

Researchers are encouraged to report Golden Negative and Golden Positive results separately.

---

## 14. Recommended Evaluation

### 14.1 Intervention Decision

Recommended metrics include:

- accuracy;
- balanced accuracy;
- `KEEP` recall;
- `EDIT` recall;
- overcorrection rate on Golden Negative;
- missed-intervention rate on Golden Positive.

### 14.2 Rewriting

Recommended dimensions include:

- bias mitigation;
- semantic preservation;
- factual preservation;
- relevance to the identified problem;
- naturalness and fluency;
- preservation of register;
- preservation of required information.

Removal of a gender-related expression alone is not sufficient for a successful rewrite.

---

## 15. Out-of-Scope Uses

The benchmark should not be used:

- to infer the gender identity of real individuals;
- as a universal or prescriptive definition of gender-inclusive Chinese;
- as a fully automatic content-moderation policy;
- to replace human review in legal, medical, or high-stakes settings;
- to evaluate languages other than Chinese without adaptation;
- to erase self-identification, factual distinctions, quotations, or protected linguistic functions.

---

## 16. Ethical Considerations

Gender-inclusive rewriting can itself cause harm when it removes identity, factual information, culturally meaningful expressions, institutional names, medical distinctions, or a speaker's intended stance. The benchmark therefore treats unnecessary intervention as a substantive evaluation failure.

Potential risks include:

- reproducing offensive or stereotypical language in Positive examples;
- overgeneralizing the taxonomy beyond its intended Chinese context;
- using automated outputs without human review;
- misinterpreting `KEEP` as endorsement of all content rather than a decision about whether gender-focused rewriting is warranted;
- misinterpreting `EDIT` as permission to change unrelated content.

The benchmark should be used with attention to context, speaker intent, and affected communities.

### Sensitive-content review

`[TODO: document whether and how sensitive, derogatory, medical, or identity-related examples were reviewed.]`

---

## 17. Personal and Identifying Information

The public release should avoid exposing unnecessary personal or identifying information.

Before release, document:

- `[TODO: whether examples contain public figures, fictional names, or constructed names.]`
- `[TODO: procedures for removing private contact details, addresses, account identifiers, and other personal data.]`
- `[TODO: whether any examples are derived from public sources and under what terms.]`

---

## 18. Language and Cultural Scope

The benchmark is specific to Chinese linguistic and cultural contexts. Relevant features include:

- omission of subjects and pronouns;
- differences among `他`, `她`, `其`, `本人`, and omitted forms;
- social and kinship titles;
- lexicalized compounds and fixed expressions;
- institutional and historical names;
- Chinese-specific false gender triggers;
- register-sensitive rewriting.

English labels are explanatory metadata and do not replace the Chinese language evidence.

---

## 19. Limitations

- The benchmark covers Chinese only.
- It does not represent all forms of gender bias or all Chinese-speaking communities.
- Some examples may allow multiple valid rewrites.
- The benchmark primarily uses sentence- or short-text-level contexts.
- Category distributions are constructed for diagnostic coverage and are not natural-frequency estimates.
- Difficulty labels are qualitative.
- Instance-level rationales remain in Chinese.
- Performance on the benchmark does not guarantee safe deployment in real-world systems.
- The taxonomy may require revision as language use and social norms evolve.

---

## 20. Dataset Splits

The core v2.4 public release does not expose an official train/dev/test split.

The benchmark is primarily intended for evaluation. Researchers creating development or retrieval partitions should:

- document the procedure;
- avoid tuning on the final evaluation set;
- report exact sample IDs used in each partition;
- consider category balance and possible near-duplicate leakage.

Any split used in the associated paper should be documented separately and reproduced in the accompanying experimental code.

---

## 21. Versioning

Current release:

```text
PAIFAR Benchmark v2.4
```

Future versions should report:

- added, removed, or revised samples;
- changes to taxonomy labels or identifiers;
- annotation corrections;
- field-schema changes;
- compatibility with previous releases.

---

## 22. Licensing

Final licensing has not yet been selected.

Before public release:

- confirm the provenance and reuse conditions of all examples;
- select a license compatible with the underlying material and annotations;
- add a complete `LICENSE` file;
- state whether code and data use different licenses.

`[TODO: insert final data license and source-attribution statement.]`

---

## 23. Citation

Citation information will be added after the associated paper becomes public.

During anonymous review, the release must not contain author names, affiliations, identifying repository links, or non-anonymous citation records.

---

## 24. Maintenance and Contact

Maintenance and contact information will be added after the anonymous review period.

Before public release, document:

- responsible maintainers;
- issue-reporting procedure;
- correction and removal policy;
- version-release policy.

---

## 25. Items Requiring Final Confirmation

The following items remain intentionally unresolved in this draft:

1. source provenance and reuse rights;
2. AI model and prompting details used for candidate expansion;
3. privacy and sensitive-content screening;
4. exact duplicate and near-duplicate detection procedures;
5. final data license;
6. post-review contact and citation information.

These details should be completed only from verified project records.
