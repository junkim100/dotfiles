---
description: Create a small set of parallelizable GitHub issues from PLAN.md (bundling tasks), and include shared context/scope in each issue
allowed-tools: Bash(ls:*), Bash(cat:*), Bash(find:*), Bash(pwd:*), Bash(git:status), Bash(git:diff), Bash(gh:*), Bash(date:*)
argument-hint: [--plan PLAN.md] [--max-issues 6] [--label trace-mvp] [--dry-run]
---

You are an engineering project manager.

Goal:
- Read the implementation plan file (default: PLAN.md).
- Create a small set of GitHub issues that bundle multiple tasks each.
- Issues must be as independent as possible so they can run in parallel.
- Every created issue must include the same shared "Context + Scope + Tech Stack + Risks/Open Questions summary" from the plan.

Inputs:
- $ARGUMENTS may include:
  - --plan <path> (default PLAN.md)
  - --max-issues N (default 6, min 2, max 12)
  - --label <label> (optional)
  - --dry-run (preview only, do not create issues)

Rules:
1. Do NOT require "Phase" headings. Support any PLAN.md that has:
   - A "Context" section (or equivalent),
   - A "Scope" section (or equivalent),
   - A "Tasks" section containing task IDs and descriptions,
   - Optional "Risks and Open Questions".
2. Keep issues high-level:
   - Each issue should contain 5–15 tasks (prefer 6–10).
   - Each task line in the issue body should be "- [ ] <ID> <short description>".
   - Do not paste full acceptance criteria per task.
3. Bundling heuristic for parallelism:
   - Prefer grouping by component boundary inferred from file paths:
     - electron/* or electron/src/* => "Desktop UI (Electron/React)"
     - src/db/* => "Database & embeddings"
     - src/capture/* => "Capture daemon"
     - src/evidence/* => "Evidence builder"
     - src/summarize/* and src/jobs/* => "Summarization & schedulers"
     - src/revise/* and src/graph/* => "Daily revision & graph"
     - src/retrieval/* and src/chat/* => "Retrieval & chat"
     - src/platform/* => "macOS permissions & integration"
     - tests/* and .github/* => "Integration & CI"
   - If a task spans multiple components, place it in the component that owns the orchestrator (e.g. daemon.py, builder.py).
   - If a group becomes too large, split it into two issues by ID order.
4. Dependency awareness:
   - Identify "foundation" tasks (project scaffolding, schema/migrations, IPC bridge).
   - If other bundles clearly depend on foundation, still create them as separate issues but mark in the issue body:
     - "Blocked by: <foundation issue title>".
   - Keep "foundation" as its own issue so other issues can proceed with partial work or stubs.
5. Idempotency:
   - Before creating an issue, search for an existing issue with the same title.
   - If it exists, skip by default and list it in the final summary.
6. Confirmation gate:
   - Always present a preview of issue titles and included task IDs.
   - Ask for explicit confirmation "yes" before calling `gh issue create`, unless --dry-run is set.

Process:

A) Locate and read PLAN
- Determine plan path:
  - If $ARGUMENTS contains --plan, use it, else PLAN.md.
- Verify the file exists. If not, stop and ask.

B) Extract shared text
- Extract:
  - Context: short paragraph(s)
  - Scope: bullet list(s)
  - Tech Stack: bullet list(s) if present
  - Risks/Open Questions: summarize into 5–10 bullets total (keep short)

C) Extract tasks
- Build a list of tasks as:
  - ID (string)
  - Description (short)
  - Files/Modules (paths if present)
- Support both markdown tables and bullet lists.
- Ignore tasks already marked complete (Status [x]).

D) Bundle tasks into issues
- Use the bundling heuristic above to assign each task to a "bundle".
- Merge small bundles and split oversized bundles so total issues <= --max-issues.
- Always include a "Foundation / Setup" issue if any setup tasks exist.

E) Preview
- Print:
  - Issue title
  - Bundle name
  - Task IDs included
  - Notes about likely dependencies (Blocked by)
- Ask for confirmation.

F) Create issues (if confirmed and not --dry-run)
- For each issue:
  - Title format:
    - "<Project>: <bundle name>" (derive <Project> from the plan title if possible)
  - Body format:
    - Link to plan: "Source of truth: <plan path>"
    - Shared: Context, Scope, Tech Stack (copied), Risks/Open Questions summary (short)
    - "Tasks" checklist (IDs + short descriptions)
    - Optional "Blocked by" line if needed
- Use GitHub CLI to create:
  - gh issue create --title "<title>" --body "<body>"
  - If --label provided, add: gh issue edit <num> --add-label "<label>"

Now do steps A–E only, and stop for my confirmation.

