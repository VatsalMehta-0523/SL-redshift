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
| AI-002 | 2026-10-18 | Acquisition (code) | Claude Code (Claude Opus 5.5) | Tested the SkyServer web API, wrote the setup, utility and download scripts | Pending owner review | `R/00_setup.R`, `R/utils_*.R`, `R/01_acquire.R` |
| AI-003 | | Inspection | | | | `R/02_inspect_clean.R` |
| AI-004 | | Cleaning | | | | `T02_cleaning_log.csv` |
| AI-005 | | Preprocessing | | | | `R/02_inspect_clean.R` |

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
- **Owner decision:** _pending review_
- **Resulting code:** files above
- **Effect on data:** `R/01_acquire.R` downloaded 120 rows × 15 columns from
  DR18 on 2026-10-18 (see `data/raw/ACQUISITION.md` for the MD5). A second run
  skipped the download and confirmed the MD5.
- **Linked decision:** D-003, D-004, D-005, D-015

<!--
EXPECTED NEXT ENTRIES (the coding agent fills these with REAL observations):

AI-003 Inspection — agent runs str(), summary(), NA/duplicate counts,
  magnitude/redshift ranges on data/raw/sdss_raw.csv and reports anomalies
  (e.g. sentinel -9999 values, objid precision, colour outliers).

AI-004 Cleaning — agent proposes rules (duplicates, NA/sentinels,
  physical ranges, 5·MAD colour outliers); owner accepts/rejects each;
  row counts copied from T02_cleaning_log.csv.

AI-005 Preprocessing — colour derivation, sampling to 100 with SEED,
  centring/scaling inside caret (fitted on training folds only).
-->
