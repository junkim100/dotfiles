# Source discovery

Use available authenticated connectors and local read-only commands. Resolve actual identities and schemas rather than hardcoding account IDs or database tables. Batch independent reads when supported, exhaust pagination for the requested scope, and record failures or truncation instead of presenting a partial search as complete.

## Identity and time

Resolve GitHub identity through the authenticated profile, Slack identity through the connected workspace, and Notion identity through person lookup or an established mention in the user's section. Git configuration is a cross-check but not sufficient to select a collaborator's section. Account display names can differ across systems.

Convert event timestamps to the reporting timezone. Search APIs with day-only or ambiguous date boundaries may need a one-day margin on either side; filter returned events to the exact interval afterward. Distinguish the actual work event from a later edit, synchronization, or import. Prefer the event's author and submitted timestamp over the container's modification date.

## Orca inventory

When `orca-cli` is installed, read its skill and load its version-matched guide. Resolve the executable as that guide directs, including `ORCA_CLI_COMMAND` or a dev build. Do not assume bare `orca` is the IDE command on Linux. If the skill is absent, inspect the available IDE CLI's help and use supported read-only operations.

The guide currently exposes these inventory operations; `ORCA` below is a placeholder for the resolved executable, not a literal command:

```text
ORCA repo list --json
ORCA worktree list --repo id:<repoId> --json
ORCA worktree ps --json
ORCA worktree show --worktree id:<repoId>::<worktreePath> --json
ORCA terminal list --worktree id:<repoId>::<worktreePath> --json
ORCA terminal read --terminal <handle> --json
```

Inventory every returned repo and locally visible folder context before deciding which work is relevant. Do not restrict collection to the current checkout, branch, or repo name. Record worktree paths, branch and PR associations, task descriptions, terminals, and timestamps when exposed. Include completed work with in-period evidence even when its terminal has closed.

Read pertinent terminals without sending input or resuming agents. A tail preview may omit the work: follow the current guide's cursor pagination, starting from `oldestCursor` when needed and continuing with `nextCursor` while output is limited. Do not change workspace visibility, status, branch, files, or running sessions to collect a report.

If supported, `ORCA search --index-status --json` reports session search availability. When indexing is enabled, search distinctive identifiers with `--scope conversation`, `--since`, `--path`, and `--cursor` as supported by current help. Inspect index lag and candidate truncation. Keyword search supplements the inventory; it cannot prove all activity was found. If search is disabled, leave it disabled and use authorized local transcript reads or terminal evidence, recording the limitation. This task covers this machine; do not extend to paired remote hosts without user scope.

## Codex and Claude Code histories

Discover all relevant homes, including account-managed profiles. These are observed starting points, not guaranteed layouts:

| Client | Candidate locations |
| --- | --- |
| Codex | `$CODEX_HOME`, `~/.codex`, their `sessions/`, `archived_sessions/`, and session indexes when present |
| Claude Code | `$CLAUDE_CONFIG_DIR`, `~/.claude`, their `projects/`, `sessions/`, and history indexes when present |
| Orca-managed profiles on macOS | `~/Library/Application Support/orca/codex-accounts/`, `claude-accounts/`, and session/runtime roots returned by the CLI |

Enumerate configured account homes rather than reading only the active account. On other platforms or Orca profiles, discover the actual application data path through supported CLI/config metadata. Avoid hardcoded account UUIDs. Do not dump environment variables, authentication files, cookies, or arbitrary application state into tool output.

Use indexes or metadata to find candidate sessions by cwd, workspace, branch, title, and activity time. A session created before Monday may contain this week's work; filter individual messages and tool events. File mtime is only a candidate filter and may reflect a copy or index rebuild. Read enough earlier context to understand new work without attributing the entire history to the week.

Inspect an actual record before parsing JSONL or other transcript formats. Extract user intent, substantive conclusions, executed commands and results, PR links, output artifacts, and unresolved blockers. Include delegated session results when they contribute to the same task, but merge them with the parent workstream. Exclude this report-generation conversation and pasted copies of old reports from accomplishment evidence.

If metadata is only available in SQLite, inspect its schema through a read-only connection. Do not mutate live databases or copy only a `.db` file while ignoring its WAL. If a consistent snapshot is necessary, use SQLite's supported backup mechanism into temporary storage. Missing or unreadable histories are a coverage gap, not proof of no work.

Keep transcript content local to the investigation. Do not paste raw transcripts into Notion, create public artifacts, or include session links, IDs, and resume commands in the report. Extract work-relevant facts and verify consequential completion claims.

## Git and GitHub

For relevant worktrees, inspect read-only Git status, changed-file summaries, and dated commits. Resolve the real remote repository. A branch or uncommitted diff does not establish when the user worked on it; correlate with session evidence. Inspect targeted diffs or artifacts where needed to support local-only accomplishments.

Use the GitHub connector or `gh` to discover the user's authored PRs, reviews, issue comments, and review comments. Search across repositories revealed by local activity and Slack. Qualifiers such as `author:`, `reviewed-by:`, `commenter:`, `involves:`, and a broad `updated:` window discover candidates, not timestamped proof of contribution.

For each candidate, fetch the PR and relevant review/comment events and filter by the user's identity and event time. Include older PRs with new activity. Distinguish submitted reviews from local drafts, approvals from comments, and a review request from an actual review. Use merge timestamps to establish cutoff status; today's `state` alone is insufficient for a historical weekly. Read linked commits, CI results, or run evidence only as needed to support the report, not to launch a new full review.

Follow API cursors or `--paginate` where supported. Split searches by repository or date when result caps are reached. Verify discovered PR links before publishing. No commits, pushes, reviews, or comments are authorized by this reporting workflow.

## Slack

Read the installed Slack search skill when available and use connected search/thread tools. Search the user's messages and replies across the window using supported `from:me` or resolved-user syntax. Separately search relevant mentions and identifiers from sessions and GitHub. Include evaluation, infrastructure, skill-lab, and research discussions when the user contributed; do not assume all work happened in a single channel.

Read the full relevant thread after discovering a hit, including follow-up pages. A thread started earlier may have this week's decisive reply. Capture the user's role, decision, blocker, and any follow-up changing the interpretation. Separate in-period events from later resolution. Search hits, bot summaries, unfurls, and mentions alone do not establish completion.

Follow linked sources and accessible attachments when they contain the reported result. An image or file pointer is not the numeric result itself. Do not post messages or change reactions, channel membership, or subscriptions. Use stable thread/message permalinks for citations.

## Notion and the evaluation wiki

Fetch the exact destination and style pages first. Use connected Notion search for relevant tasks, documents, and contributions in the interval. Page edits can come from another contributor or a shared synced block, so inspect content before attributing an update to the user.

Read the wiki as an index to evidence, not a replacement for live Notion and Slack. `weekly-meeting-logs.md` helps locate report history; `raw-source-status.md` describes coverage limits, and `raw-manifest.md` maps missing `raw/...` snapshots to original URLs. Follow relevant topic pages, then verify claims used in the entry. Preserve source-access gaps in coverage notes.

Before a Notion write, read the active tool's editing instructions and enhanced Markdown specification. Target only the user's section and preserve native references, surrounding contributors, and synced blocks. If a tool returns truncated content, unknown blocks, or an asynchronous task, resolve the affected target content or task status before treating the edit as verified.

## Coverage check

Check that each requested source family was inventoried and its relevant in-period records read, with pagination completed or a specific limitation recorded. Reconcile duplicate workstreams, explain contradictions through primary evidence, and verify the destination's current personal section. If a connector is unavailable, finish useful local work and produce an accurately scoped report; never claim comprehensive coverage or a successful write that was not verified.
