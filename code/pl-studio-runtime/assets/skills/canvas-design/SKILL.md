---
name: canvas-design
description: Create beautiful visual art in .png and .pdf documents using design philosophy. You should use this skill when the user asks to create a poster, piece of art, design, or other static piece. Create original visual designs, never copying existing artists' work to avoid copyright violations.
license: Complete terms in LICENSE.txt
---

# Canvas design

Create original static visual work for the user's brief. When asked to create a finished artwork, deliver a PNG or PDF suited to the brief (or the format the user requests), together with a concise Markdown design concept. If the user explicitly asks only for the concept, do not create an artwork. Do not copy an existing artist's work.

## 1. Form a design concept

First identify the task, required content, intended audience, output format, existing design direction, and explicit constraints. These govern the work. Use creative freedom only for details the user has left open; an artistic preference is never a reason to disregard the brief.

Write a short design concept that gives the work a coherent visual point of view. Describe how composition, space, color, form, material or texture, scale, rhythm, and typography support the subject. Make clear what information should be conveyed visually and what text is essential. Choose a layout appropriate to the content rather than forcing an abstract style or template onto it.

## 2. Express the concept on the canvas

Translate the concept into the requested canvas and format. Establish composition, hierarchy, palette, typography, margins, and spacing deliberately. Use negative space and visual detail in proportion to the brief; include multiple pages only when requested. For a requested series or multi-page work, maintain a consistent visual language while giving each page a distinct composition, variation, or narrative progression rather than repeating the same page. Keep all text and graphic elements within the canvas, with enough separation to avoid accidental collisions.

Use available resources before seeking new ones. The skill's `canvas-fonts` directory contains bundled font assets; locate skill resources using the current session's provided resource access, not an assumed shell working directory, physical installation path, or fixed tool name. Treat those assets as read-only. Do not assume authorization to download fonts or install dependencies. Do not install anything automatically or search unrelated environments; follow the current session's authorization, and report any resource limitation that prevents the requested result.

Save temporary files and previews in the current session's designated locations, and deliver finished files to the current session's designated delivery location unless the user specifies another location. Do not hard-code temporary-directory, session-specific absolute, or machine-specific paths.

## 3. Inspect and refine

Review the actual final preview whenever the environment makes it available. Check that text and graphics stay within bounds, do not overlap unintentionally, have suitable breathing room, and remain legible at the intended viewing size. Revisit hierarchy, spacing, contrast, alignment, and consistency; make focused refinements that improve the brief's intended effect rather than adding detail for its own sake. Review the result once more after changes.

If the environment cannot provide a visual preview, say that visual inspection was not completed. Structural checks alone do not establish that the artwork looks correct.
