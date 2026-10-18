# CONTRIBUTING.md

Guidelines for anyone contributing to this project: the owner, teammates,
or AI coding agents. Agents should also follow [AGENTS.md](AGENTS.md).
[TASK.md](TASK.md) is the absolute specification.

---

## 1. Before you start

1. Read `TASK.md` (what) and `AGENTS.md` (how).
2. Check `DECISIONS.md`. Don't redo a decision that has already been made.
3. Open the `sdss-photoz-r/` folder (renv activates automatically) and
   restore the packages (README §4):
   ```bash
   Rscript -e "renv::restore(prompt = FALSE)"
   ```
4. Make sure `data/raw/sdss_raw.csv` exists (see README §5).

---

## 2. Workflow

1. **Branch** from `main`:
   - `feat/<thing>`: new script, model, figure
   - `fix/<thing>`: bug fix
   - `docs/<thing>`: documentation only
   - `report/<thing>`: report text and layout
2. **Make a focused change.** One branch should do one thing.
3. **Run the pipeline and tests** (§6).
4. **Update the docs** that your change touches (§7).
5. **Commit** (§4) and open a pull request using the checklist (§8).

Working solo? Committing straight to `main` is fine, but still follow the
commit format and run the checks.

---

## 3. Code style

- Follow the [tidyverse style guide](https://style.tidyverse.org/).
  Run `styler::style_dir("R")` before committing.
- `lintr::lint_dir("R")` should report no new issues.
- Use `snake_case` for objects and functions, and `UPPER_CASE` for constants
  (`SEED`, `PATHS`).
- Use the native pipe `|>`.
- Build all paths with `here::here()`. No `setwd()`, no absolute paths.
- Every script starts with the header block described in AGENTS.md §4.
- Comments explain **why**, especially the physics.
  ```r
  # g − r tracks the 4000 Å break moving from g into r as z increases
  ```
- Keep functions short. Shared logic goes in `R/utils_*.R`.
- Never write results to disk by hand. Only scripts write to `outputs/`.

---

## 4. Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <summary in imperative, ≤ 72 chars>

<optional body: what and why>
Refs: D-0xx, TASK step N
```

| type | use for |
|---|---|
| `feat` | new functionality (model, figure, script) |
| `fix` | bug fix |
| `data` | acquisition / cleaning changes |
| `docs` | markdown / comments |
| `report` | report.Rmd |
| `test` | tests |
| `chore` | renv, gitignore, tooling |

Examples:
```
feat(train): add SVR radial model with C/sigma grid
data(clean): remove colour outliers beyond 5 MAD
Refs: D-005, TASK step 2
```

---

## 5. Common contributions

### 5.1 Adding a new model
1. Propose it in `DECISIONS.md` (new D-entry, status `Proposed`) and get
   the owner's approval.
2. Add an ID and colour to `MODEL_IDS` / `MODEL_COLOURS` in `R/utils_plot.R`.
3. Train it in `R/05_train.R` with the **shared CV folds**, and save it to
   `outputs/models/<id>.rds`.
4. Add a tuning figure if it has hyperparameters.
5. Make sure `06_evaluate.R` picks it up automatically. It loops over the
   saved models.
6. Update README §9 (Models) and `docs/REPORT_GUIDE.md`.

### 5.2 Adding a new figure
1. Assign the next free ID (`F21`, …) in `docs/REPORT_GUIDE.md`, with its
   purpose, content, size and report section.
2. Build it with `theme_report()` and save it with `save_fig()`.
3. Append a draft caption to `outputs/figures/captions.md`.

### 5.3 Changing cleaning rules
1. Never edit `data/raw/`.
2. Change `R/02_inspect_clean.R`. Each rule must write a row to
   `T02_cleaning_log.csv`.
3. Log the AI interaction in `docs/AI_USAGE.md` if an AI suggested it.
4. Re-run the whole pipeline, because downstream results will change.

### 5.4 Changing the dataset
Only allowed through a new decision that supersedes D-003/D-015. The final
analysis dataset must stay within 30–100 rows (TASK.md C1).

---

## 6. Checks before every commit

```bash
Rscript -e "styler::style_dir('R')"
Rscript -e "lintr::lint_dir('R')"
Rscript run_all.R
Rscript -e "testthat::test_dir('tests/testthat')"
```

Before finishing work on the report:
```bash
Rscript -e "rmarkdown::render('report/report.Rmd', output_format = 'all')"
```

---

## 7. Documentation you must keep in sync

| If you change… | Update… |
|---|---|
| Data query / cleaning | README §5–6, `docs/AI_USAGE.md`, `DECISIONS.md` |
| Features / models / metrics | README §8–10, `DECISIONS.md`, `docs/REPORT_GUIDE.md` |
| Figures / tables | `docs/REPORT_GUIDE.md`, captions.md |
| Packages | `renv::install()` then `renv::snapshot()`, README §4 |
| Results (after re-run) | README §12 from `outputs/tables/T05_test_metrics.csv` |

---

## 8. Pull request checklist

```markdown
- [ ] Linked to TASK.md step(s): ___
- [ ] Linked decision(s): D-___ (new or existing)
- [ ] `run_all.R` passes in a fresh session
- [ ] Tests pass
- [ ] No changes to data/raw/
- [ ] Test set not used for tuning/selection
- [ ] Figures saved via save_fig(), captions added
- [ ] Docs updated per CONTRIBUTING §7
- [ ] AI usage logged (if AI suggested data handling)
- [ ] No hand-typed result numbers
```

---

## 9. Using AI assistants in this project

AI assistance is **part of the assignment** (brief step 2), and it must be
transparent:
- Log prompts and outcomes in `docs/AI_USAGE.md`.
- Review and understand every line of AI-written code before you accept it.
  You must be able to explain it in a viva.
- Never accept AI-generated "data" or "results". Only code and suggestions.
