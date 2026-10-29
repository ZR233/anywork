---
name: office-recalculate
description: Refresh spreadsheet formula caches and verify calculated values with LibreOffice Kit.
---

# Recalculate spreadsheet formulas

First locate an already configured or installed usable LibreOffice Kit command, or a configured Node executable and Kit CLI path. Do not assume a bundled Kit, fixed installation path, or that a command on PATH is the intended installation. If none is available, finish checks that do not require recalculation and report the unavailable operation. Follow [sidecar setup](references/sidecar.md) only within existing user authorization. If an installed Kit fails, report its failure; do not substitute system soffice or another engine.

Keep the original workbook and write a new file in the current session scratch directory for temporary files; use artifacts or the requested location for deliverables. Quote each input and output path.

```text
"<configured Node executable>" "<configured Kit CLI path>" recalculate --input <workbook.xlsx> --output <recalculated.xlsx>
```

Verify the saved result with openpyxl, using the already configured project or session Python environment. Open it with both `data_only=False` and `data_only=True`. Check that formulas survive and cached results match the requested logic, expected totals, and cell types. Check required unchanged sheets, styles, and data. Recalculation does not validate business logic or guarantee Excel-specific feature compatibility.

If no supported recalculation engine is available or the command fails, preserve the workbook and explain that calculated values could not be refreshed. Do not replace requested formulas with constants or present stale/absent caches as fresh results. Deliver the verified output using the current session's supported file delivery method, keeping the file in place.
