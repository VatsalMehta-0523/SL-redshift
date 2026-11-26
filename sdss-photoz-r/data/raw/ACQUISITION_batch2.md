# ACQUISITION_batch2.md — provenance of data/raw/sdss_raw_batch2.csv

Written by `R/01_acquire.R`. Do not edit by hand. The raw file is frozen (D-015).

| Item | Value |
|---|---|
| Date (UTC) | 2026-11-26 11:07:45 |
| Data release | DR18 |
| Method | SkyServer SqlSearch web service via R/01_acquire.R (httr2) |
| Endpoint | https://skyserver.sdss.org/dr18/SkyServerWS/SearchTools/SqlSearch |
| Rows | 30 |
| Columns | objid, u, g, r, i, zmag, err_u, err_g, err_r, err_i, err_z, redshift, redshift_err, ra, dec |
| MD5 of sdss_raw_batch2.csv | `f7360610c83e447707e03ae7c72b1220` |
| R version | R version 4.6.1 (2026-06-24 ucrt) |

## Query (`data/sql/sdss_query_batch2.sql`)

```sql
-- =============================================================================
-- sdss_query_batch2.sql — second SDSS pull for dataset version v2 (DR18)
-- Identical selection to sdss_query.sql (same columns, same cuts D-005);
-- only the row count differs. Returns 30 random galaxies, of which 20 are
-- kept after cleaning (D-018). Galaxies already in batch 1 are removed in
-- R/02b_extend_v2.R, so the two batches never overlap.
-- Decisions: D-004 (source), D-005 (cuts), D-015 (frozen raw), D-018 (v2)
-- =============================================================================
SELECT TOP 30
    p.objid,
    p.dered_u   AS u,
    p.dered_g   AS g,
    p.dered_r   AS r,
    p.dered_i   AS i,
    p.dered_z   AS zmag,        -- z-BAND MAGNITUDE (not redshift!)
    p.err_u, p.err_g, p.err_r, p.err_i, p.err_z,
    s.z         AS redshift,    -- spectroscopic redshift (target)
    s.zErr      AS redshift_err,
    p.ra, p.dec
FROM PhotoObj AS p
JOIN SpecObj  AS s ON s.bestobjid = p.objid
WHERE s.class    = 'GALAXY'
  AND s.zWarning = 0
  AND p.clean    = 1
  AND p.dered_r BETWEEN 14 AND 17.77
  AND s.z > 0.01 AND s.z < 0.5
  AND p.err_u < 0.2 AND p.err_g < 0.2 AND p.err_r < 0.2
  AND p.err_i < 0.2 AND p.err_z < 0.2
ORDER BY NEWID()
```

The query uses `ORDER BY NEWID()`, so re-running it returns *different*
galaxies. This record and `sdss_raw_batch2.csv` are the frozen copy (D-015).
