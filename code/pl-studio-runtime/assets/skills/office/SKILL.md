---
name: office
description: Choose an appropriate workflow for creating, editing, inspecting, or converting Office documents and spreadsheets.
---

# Office task routing

Use the current session's skill discovery and loading mechanism to find the focused capability for the requested operation. Each Office capability is independently usable; do not require this routing guide or another Office skill as setup.

- For Word documents, PowerPoint presentations, or Excel workbooks, discover the matching document-format capability.
- For image export or visual inspection, discover document rendering; honor an explicit request to skip rendering.
- For refreshed spreadsheet formula results, discover spreadsheet recalculation.
- For PDF output, discover Office-to-PDF export. This is an Office export workflow, not general PDF editing.

Discover only capabilities needed for the task. Do not assume a particular tool interface or a fixed loading sequence.
