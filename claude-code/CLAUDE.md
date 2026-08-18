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
