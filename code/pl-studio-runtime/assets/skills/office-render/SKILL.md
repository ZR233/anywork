---
name: office-render
description: Render requested document images or inspect visual layout with LibreOffice Kit.
---

# Document images and visual inspection

First locate an already configured or installed usable LibreOffice Kit command, or a configured Node executable and Kit CLI path. Do not assume a bundled Kit, fixed installation path, or that a command on PATH is the intended installation. If none is available, finish checks that do not require rendering and report the unavailable operation. Follow [sidecar setup](references/sidecar.md) only within existing user authorization. If an installed Kit fails, report its failure; do not substitute another renderer, system soffice, or package-fetch command.

Before generating images only for inspection, establish that image inspection is supported in the current session. Otherwise finish the applicable content and structure checks and report the requested visual check as unavailable. Do not generate unreadable previews, retry image reads, or choose a second model. Requested image exports can still be delivered.

## Render the saved deliverable

Keep temporary inputs and inspection-only previews under the current session scratch directory; put requested deliverables in artifacts or the user-requested location. For requested image exports, use the requested output directory and retain the images. For inspection-only previews, create a unique directory within session scratch and give the renderer an output child path that does not yet exist if the renderer creates it. Keep it until inspection finishes, then remove only that task-owned preview directory. Quote each input and output path. Report inspection results in text; do not link or embed removed previews.

```text
"<configured Node executable>" "<configured Kit CLI path>" render --input <final-file> --output-dir <new-directory> --pages "1,3,4"
"<configured Node executable>" "<configured Kit CLI path>" render --input <final-workbook.xlsx> --output-dir <new-directory> --sheet <exact-name> --range <A1-range>
```

For DOCX, PPTX, or PDF, batch requested pages/slides in one call. In PowerShell, quote comma-separated `--pages` values so they remain one argument. Inspect all pages only for a requested whole-document review. For worksheets, choose the exact affected range, including chart/drawing regions; worksheet numbers are not PDF page numbers. Inspect the final saved file, reuse existing images for an unchanged source, and rerender only after requested source changes or for previously unrendered regions. Change print areas or scaling only when the user requests print layout.

Read the returned JSON manifest for image paths, page counts, fragment rectangles, and missing-font diagnostics. Use the image-reading capability provided by the current session to inspect the requested images. Check clipping, alignment, headings, table widths, contrast, chart labels, and number formats as relevant to the task. A successful command or image read alone does not establish a usable preview; guessed text geometry does not establish overflow.

## Failed or blank previews

For populated content, a fully transparent or uniformly blank image is a renderer failure. If a pixel check is needed, composite RGBA onto white first; raw RGB under transparent pixels can look nonblank. Check once and do not reread the same image. Stop visual checks for the task immediately after a blank result. This overrides the rerender-after-edit guidance above: do not render or read images again, even after editing or copying the source, or try another range, page, sheet, DPI, output format, diagnostic export, or print setting. Preserve the usable source and requested outputs and finish applicable content/data checks.

If content and structure checks pass, name the saved file and verified edits as needed, then include exactly one visual-status sentence: "Content and structure checks passed; visual inspection was not completed." in English, or "内容与结构检查通过；视觉检查未完成。" in Chinese. Do not add a render or preview bullet, explain why inspection stopped, or describe the image or pixels. Report content or structure failures separately; never say all checks passed or claim visual verification.

LibreOffice output can differ from Word, PowerPoint, or Excel. Images do not certify animation/media playback, refresh formula caches in the source workbook, or guarantee native application fidelity. Deliver requested files using the current session's supported file delivery method; keep the files in place. Do not deliver inspection images or reports unless requested.
