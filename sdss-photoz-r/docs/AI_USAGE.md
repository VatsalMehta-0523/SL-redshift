# AI_USAGE.md — Log of AI-Assisted Work (Workflow Step 2)

> The brief requires: **"Use AI tools to inspect, clean, and preprocess the
> dataset."** This file is the evidence. It is **append-only**. Every time an
> AI tool (Claude, a coding agent, ChatGPT, Copilot…) inspects the data,
> flags a problem, proposes a cleaning or preprocessing rule, or writes or
> reviews code, add an entry. Summarise it in the report's Data section and
> include the full log as an appendix.

**Rules**
- Be honest. Record suggestions you rejected as well as ones you accepted.
- The owner (student) makes every final decision. The AI only proposes.
- AI must never supply data values or results, only analysis, code and
  suggestions.
- Link each entry to the code it produced and to any `DECISIONS.md` entry.

---

## Summary table (keep updated)

| ID | Date | Stage | Tool | What the AI did | Owner decision | Code / output |
|---|---|---|---|---|---|---|
| AI-001 | 2026-10-18 | Planning | Claude (claude.ai) | Proposed project, features, models, metrics, query cuts; drafted project docs | Accepted (D-001–D-016) | This doc pack |
| AI-002 | 2026-10-18 | Acquisition (code) | Claude Code (Claude Opus 5.5) | Tested the SkyServer web API, wrote the setup, utility and download scripts | Accepted | `R/00_setup.R`, `R/utils_*.R`, `R/01_acquire.R` |
| AI-003 | 2026-10-18 | Inspection | Claude Code (Claude Opus 5.5) | Checked structure, NA, sentinels, duplicates, ranges, errors, colour outliers; flagged 2 very blue galaxies | Noted | `outputs/logs/02_inspection.txt` |
| AI-004 | 2026-10-18 | Cleaning | Claude Code (Claude Opus 5.5) | Implemented rules 1–9; suggested flag-only for the 2 blue galaxies | Rejected the suggestion: removed them as planned | `R/02_inspect_clean.R`, `T02_cleaning_log.csv` |
| AI-005 | 2026-10-18 | Preprocessing | Claude Code (Claude Opus 5.5) | Derived colours, seeded sample to 100, column order | Accepted (scaling deferred to caret, D-010) | `R/02_inspect_clean.R` |

---

## Entry template

```markdown
### AI-0xx — <short title>
- **Date:** YYYY-MM-DD
- **Stage:** Inspection | Cleaning | Preprocessing | Modelling | Code review | Report
- **Tool / model:** e.g. Claude Code (Claude Opus), ChatGPT, Copilot
- **Input given to AI:** what it saw (e.g. `str()`/`summary()` output,
  first 10 rows, NA counts). Never paste more data than needed.
- **Prompt (short):** "…"
- **AI output / suggestion:** what it found or proposed
- **Owner decision:** Accepted / Modified / Rejected, and why
- **Resulting code:** file + line range or function name
- **Effect on data:** rows before → after (from T02), columns added
- **Linked decision:** D-0xx (if any)
```

---

## Entries

### AI-001 — Project planning and documentation
- **Date:** 2026-10-18
- **Stage:** Planning
- **Tool / model:** Claude (claude.ai)
- **Input given to AI:** Unit 4 brief (PDF), the chosen topic "Photometric
  redshift prediction using SDSS data".
- **AI output / suggestion:** a SkyServer SQL query with quality cuts; colour
  features (u−g, g−r, r−i, i−z) + r magnitude; models (baseline, LM, kNN, RF,
  SVR, optional XGBoost); photo-z metrics (σ_NMAD, η); repository structure,
  figure list and these guidance documents.
- **Owner decision:** Accepted, pending instructor confirmation of topic (D-001).
- **Resulting code:** none yet (`data/sql/sdss_query.sql`, docs).
- **Linked decision:** D-001 to D-016.

### AI-002 — Data acquisition scripts
- **Date:** 2026-10-18
- **Stage:** Acquisition (code)
- **Tool / model:** Claude Code (Claude Opus 5.5)
- **Input given to AI:** the project docs and `data/sql/sdss_query.sql`. No
  data values were given.
- **Prompt (short):** "Write the data collection scripts."
- **AI output / suggestion:**
  - Tested the SkyServer SqlSearch web service with throw-away `TOP 3` and
    `TOP 5` queries, outside the repository. Findings: DR18 accepts the
    project query unchanged and returns all 15 expected columns in about 15 s.
    The response starts with a `#Table1` line before the CSV header. `objid`
    values have 19 digits, so they must be read as text. SQL errors come back
    as HTTP 500 with a JSON `ErrorMessage`.
  - Wrote `R/00_setup.R` (packages, `SEED`, paths, data contract),
    `R/utils_metrics.R`, `R/utils_plot.R` and `R/01_acquire.R`. The
    acquisition script downloads via the web service (DR18, then DR17), strips
    `#Table1`, checks the header and row count, writes `ACQUISITION.md` with an
    MD5 checksum, and on later runs refuses to download again and stops if
    the raw file's MD5 has changed (D-015).
  - Added a `.here` file. The git repository root is the parent folder
    (`Kavya-jini/`), so without it `here::here()` would resolve paths
    there instead of inside `sdss-photoz-r/`.
- **Owner decision:** Accepted. The owner reviewed the scripts and committed
  them.
- **Resulting code:** files above
- **Effect on data:** `R/01_acquire.R` downloaded 120 rows × 15 columns from
  DR18 on 2026-10-18 (see `data/raw/ACQUISITION.md` for the MD5). A second run
  skipped the download and confirmed the MD5.
- **Linked decision:** D-003, D-004, D-005, D-015

### AI-003 — Inspection of the raw data
- **Date:** 2026-10-18
- **Stage:** Inspection
- **Tool / model:** Claude Code (Claude Opus 5.5)
- **Input given to AI:** output of `str()`, `summary()`, NA, sentinel and
  duplicate counts, colour summaries and MAD outlier counts for
  `data/raw/sdss_raw.csv`. The full output is saved in
  `outputs/logs/02_inspection.txt`.
- **Prompt (short):** "Inspect the raw data and flag anything the cleaning
  rules must handle."
- **AI output / suggestion:**
  - 120 rows × 15 columns. No NA, no sentinel values (±9999), no duplicate
    `objid`, no fully duplicated rows, and no repeated sky positions.
  - All `objid` values have 19 digits and are intact as text.
  - All magnitudes lie well inside [10, 30] and redshift inside (0, 1). All
    magnitude errors are below the query's 0.2 cut.
  - The redshift range (about 0.025–0.22) is narrower than D-005 expected.
    At these redshifts the 4000 Å break stays inside the g band, which matters
    for the physics discussion.
  - With the 5·MAD rule, 2 galaxies are flagged, both on `i_z`:
    `1237665548892962975` (z = 0.031) and `1237657769630695800` (z = 0.050).
    Both are blue in **all four** colours, not just one. The first has
    typical photometric errors; the second has errors about 2–4× the sample
    median but well under the 0.2 cut. The AI judged them to be real blue
    star-forming galaxies rather than bad photometry, since bad photometry
    usually shifts a single colour.
- **Owner decision:** Noted. See AI-004 for how the outliers were handled.
- **Resulting code:** inspection block (step 2) of `R/02_inspect_clean.R`
- **Effect on data:** none (inspection only)
- **Linked decision:** D-012

### AI-004 — Cleaning rules
- **Date:** 2026-10-18
- **Stage:** Cleaning
- **Tool / model:** Claude Code (Claude Opus 5.5)
- **Input given to AI:** the AI-003 findings and the rules in README §6.
- **Prompt (short):** "Implement the cleaning pipeline; ask before changing
  any planned rule."
- **AI output / suggestion:** implemented rules 1–9 from README §6, with one
  row per rule in T02 (including rules that remove nothing). For rule 6 it
  suggested **flagging the two blue galaxies without removing them**: they look
  physically real, and removing them leaves the model with almost no blue
  galaxies to learn from.
- **Owner decision:** **Rejected the flag-only suggestion.** Rule 6 was
  applied as planned and both galaxies were removed. Every other rule was
  accepted as written.
- **Resulting code:** `R/02_inspect_clean.R`, steps 3–6
- **Effect on data (from T02):** 120 → 120 (rules 3–5 removed nothing) →
  118 (rule 6 removed 2)
- **Linked decision:** D-012
- **Note for the report:** after this cut the sample has no very blue
  galaxies, so the models are not tested on them. Mention this in
  Limitations.

### AI-005 — Preprocessing
- **Date:** 2026-10-18
- **Stage:** Preprocessing
- **Tool / model:** Claude Code (Claude Opus 5.5)
- **Input given to AI:** the cleaned 118 rows (no data values beyond what
  AI-003 lists).
- **Prompt (short):** "Derive features and produce the 100-row analysis set."
- **AI output / suggestion:** derive the colours `u_g, g_r, r_i, i_z`; sample
  exactly 100 rows with `set.seed(42)`; sort by `objid` and fix the column
  order; assert 30 ≤ n ≤ 100, no NA and unique `objid`. Centring and scaling
  are **not** done here. They run inside `caret::train()` on each training
  fold, so the test set cannot leak into them.
- **Owner decision:** Accepted
- **Resulting code:** `R/02_inspect_clean.R`, steps 7–9
- **Effect on data (from T02):** 118 → 100 rows (random sample); 4 colour
  columns added (19 columns in total). Verified: colours equal magnitude
  differences, values match the raw file, and a re-run gives a
  byte-identical `sdss_clean.csv`.
- **Linked decision:** D-003, D-006, D-010, D-014
