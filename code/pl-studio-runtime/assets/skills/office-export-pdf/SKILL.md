---
name: office-export-pdf
description: Convert an Office document to a requested PDF with LibreOffice Kit.
---

# Export an Office document to PDF

First locate an already configured or installed usable LibreOffice Kit command, or a configured Node executable and Kit CLI path. Do not assume a bundled Kit, fixed installation path, or that a command on PATH is the intended installation. If none is available, finish work that does not require export and report the unavailable operation. Follow [sidecar setup](references/sidecar.md) only within existing user authorization. If an installed Kit fails, report its failure; do not substitute system soffice or another converter.

Convert the final saved Office file to a new PDF in the current session scratch directory for temporary files; use artifacts or the requested location for deliverables. Preserve the source. Quote each input and output path.

```text
"<configured Node executable>" "<configured Kit CLI path>" convert --input <final-office-file> --output <new-file.pdf>
```

Check the command result, nonempty output, and `%PDF-` file signature, then report that extent of validation. Unless the user requests deeper checks, do not search for PDF readers, generate images, or install tools to validate a conversion. Spreadsheet PDF pages follow workbook print settings; change those settings only when requested. Conversion may differ from the native application's pagination or fonts.

If export fails, preserve the usable source and report the export limitation. Do not repeatedly convert an unchanged source or use conversion to investigate a failed preview. For PDF export alone, stop after these checks. Only a request for images or visual inspection calls for the available document-rendering capability; load it before that separate operation. Deliver the requested PDF using the current session's supported file delivery method, keeping the file in place.
