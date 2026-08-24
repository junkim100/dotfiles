# No Hard-Wrapped Prose

**One logical line per paragraph, list item, or heading; never wrap prose at a column width.**

- Applies everywhere prose lives: markdown files, docstrings, code comments, YAML/config comments, commit message bodies.
- A newline is a semantic boundary (new paragraph, new list item, table row, code fence), never a cosmetic one.
- Code itself follows the language formatter (ruff line limits etc.); this rule governs natural-language text only.
- When editing an existing hard-wrapped file, reflow the paragraphs you touch; verify content is unchanged (whitespace-collapsed equality) when reflowing in bulk.

# No Em Dashes

**Never use em dashes (—) or en dashes (–) in prose.**

- Applies everywhere prose lives: chat responses, markdown files, docstrings, code comments, commit messages, PR descriptions.
- Rewrite instead: use a period for two separate thoughts, a colon before an explanation or list, a comma for a light aside, or parentheses for a true aside.
- Do not swap in a spaced hyphen ( - ) as a stand-in; restructure the sentence.
- Hyphens in compound words (well-known, end-to-end) and ranges written with a hyphen or "to" are fine.
- Leave verbatim quotes, cited text, and third-party content unchanged.

# Never Publish Claude Session Links

**Never include a Claude session or conversation link in anything you write.**

- Applies to PR descriptions, PR and issue comments, commit messages, code comments, docs, Slack messages, emails, and any other outward-facing text.
- Covers any URL that points at a Claude session or transcript, including claude.ai/code links, session share links, and cloud session URLs, as well as raw session IDs presented as a way to reach the conversation.
- The "Generated with Claude Code" attribution line and the Co-Authored-By trailer are fine, as long as they carry no session link.
- If the user explicitly asks for the session link in a specific place, share it there and nowhere else.
