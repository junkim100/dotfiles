---
description: Read PRD.md, ask clarifying questions, generate PLAN.md, and (with confirmation) update CLAUDE.md with the planning workflow
allowed-tools: Bash(ls:*), Bash(find:*), Bash(cat:*), Bash(pwd:*), Bash(git:status), Bash(git:diff), Bash(git:add), Bash(git:commit), Bash(cp:*), Bash(mv:*)
argument-hint: [--prd PRD.md] [--plan PLAN.md] [--no-commit]
---

You are a senior engineer helping to turn a PRD into a concrete implementation plan for this repository, and also helping maintain CLAUDE.md with the right planning workflow.

High level flow:

1. Inspect the repository to find the main PRD file, usually `PRD.md` in the root or in `docs/` or `specs/`.
2. Read the PRD and any obviously related design docs.
3. Ask me a focused batch of clarifying questions about:
   - Business goals and success metrics
   - Constraints and non-goals
   - Target platforms and tech stack (frontend, backend, infra, data)
   - Integration points and external services
   - Deployment, observability, and security requirements
4. Use my answers, plus the PRD, to generate or update `PLAN.md` in the repo root.
5. Propose updates to `CLAUDE.md` to reference the new planning workflow.

Rules and behavior:

- Work in THREE phases:

  Phase A, Clarify:
  - First, locate and read the PRD.
  - Present a numbered list of **no more than 12** clarifying questions.
  - Group questions by topic (Requirements, Tech stack, Architecture, Risks, Open questions).
  - Wait for my answers before you touch any files.

  Phase B, Create PLAN.md:
  - Once I answer, summarize what you learned in 5–10 bullet points.
  - Create (or update) `PLAN.md` with:
    - `# Implementation plan: <feature or project name>`
    - `## Context` (cite PRD file used)
    - `## Scope`
    - `## Tasks` (each with ID, Description, Files/modules, Acceptance criteria, Status `[ ]`)
    - `## Risks and open questions`

  Phase C, Update CLAUDE.md:
  - Read current `CLAUDE.md`.
  - Find the section for "Planning workflow" or create one under `## Workflow`.
  - Propose an addition like:
    ```
    ## Planning workflow

    - For any non trivial feature or change:
      - First run `/plan-from-prd`.
      - Answer all clarifying questions in detail.
      - Review the generated `PLAN.md` and edit it manually if needed.
      - Only then start implementation work (including any Ralph style loops).
    - Treat `PLAN.md` as the single source of truth for implementation tasks for this branch.
    ```
  - Show me exactly what you propose to ADD to `CLAUDE.md` (do not rewrite the whole file).
  - Ask me to confirm before writing the change.
  - If confirmed, append the planning workflow section to `CLAUDE.md` under an `## Planning workflow` header.

Safety and editing rules:

- **For PLAN.md**: Never discard existing content without quoting what you plan to change and asking for confirmation if major.
- **For CLAUDE.md**:
  - Never rewrite the whole file. Only append or update the "Planning workflow" section.
  - If "Planning workflow" already exists, show the diff of what you propose to change.
  - Backup the original `CLAUDE.md` as `CLAUDE.md.backup` before any edit.
  - Commit the changes to git with a message like "feat: add planning workflow to CLAUDE.md and create PLAN.md for <feature>".
- If the PRD is missing or ambiguous, stop and ask me what to do next instead of guessing.
- Do NOT write any application code during this command.

Now:

1. Search the repo for a PRD file (`PRD.md`, `docs/prd*.md`, `specs/*.md`).
2. Tell me which file(s) you found.
3. Ask your clarifying questions in a single numbered list.

