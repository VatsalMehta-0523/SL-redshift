# ACQUISITION.md — provenance of data/raw/sdss_raw.csv

Written by `R/01_acquire.R`. Do not edit by hand. The raw file is frozen (D-015).

| Item | Value |
|---|---|
| Date (UTC) | 2026-10-18 07:50:39 |
| Data release | DR18 |
| Method | SkyServer SqlSearch web service via R/01_acquire.R (httr2) |
| Endpoint | https://skyserver.sdss.org/dr18/SkyServerWS/SearchTools/SqlSearch |
| Rows | 120 |
| Columns | objid, u, g, r, i, zmag, err_u, err_g, err_r, err_i, err_z, redshift, redshift_err, ra, dec |
| MD5 of sdss_raw.csv | `f319eeaeda6b75e6fbbb72a49d4d43ca` |
| R version | R version 4.6.1 (2026-06-24 ucrt) |

## Query (`data/sql/sdss_query.sql`)

```sql
-- =============================================================================
-- sdss_query.sql — SDSS SkyServer query for the photo-z project (DR18)
-- Run at: https://skyserver.sdss.org/dr18/SearchTools/sql   (Output: CSV)
-- Returns 120 random galaxies (cleaning buffer; analysis uses exactly 100).
-- Decisions: D-003 (size), D-004 (source), D-005 (cuts), D-015 (frozen raw)
-- =============================================================================
SELECT TOP 120
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
galaxies. This record and `sdss_raw.csv` are the frozen copy (D-015).
