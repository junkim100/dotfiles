#!/usr/bin/env python3
"""Local ledger of pr-review runs.

Each review gets one directory holding review.json, written by the review (Phase 7.6), and outcome.json, written by `outcomes` after the user has had a chance to post. The ledger answers three questions the skill could not answer before: which drafts the user posted unchanged, which ones they edited or dropped, and why (from session feedback).

Records live under ~/.local/state/pr-review/reviews/ by default. Directories under ~/.local/state/slack-pr-review/reviews/ are scanned too, so reviews started by the Slack loop land in the same ledger when their worker passes its report directory as report-dir.

review.json (input to `save`, JSON on stdin or already in <dir>/review.json):
  {
    "repo": "owner/repo", "pr": 123, "head": "<sha>",            required
    "verdict": "one line",                                         required
    "drafts": [                                                    required, may be empty
      {"id": "D1", "channel": "post" | "held", "body": "...",      required per draft
       "file": "path" | null, "line": 12 | null,
       "held_reason": "<code>" (required when channel is held; see HELD_REASONS),
       "kind": "defect" | "question", "blocking": true, "severity": "High", "impact": "primary",
       "why": "one plain-English line", "mechanism": "kebab-slug"}
    ],
    "base": "main", "target_sha": "<sha>", "mode": "standard" | "blocking" | "all", "followup": false,
    "agent": "claude-code" | "codex", "model": "...", "started_at": "<ISO 8601 UTC>",
    "gaps": ["..."], "checklist": [{"item": "item 7", "result": "violation", "evidence": "path:line"}]
  }
`save` adds saved_at and skill_version, keeps earlier feedback, and keeps each draft's first wording as first_body when a later save changes it.
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
DEFAULT_ROOT = STATE / "pr-review" / "reviews"
EXTRA_ROOTS = [STATE / "slack-pr-review" / "reviews"]
SKILL_DIR = Path(__file__).resolve().parent.parent

HELD_REASONS = {
    "unreachable-in-practice",
    "inherited",
    "cosmetic",
    "low-priority",
    "ci-visible",
    "duplicate",
    "house-rule",
    "accepted",
    "not-actionable",
    "mode",
}
FEEDBACK_ACTIONS = {"edit", "drop", "accept", "missed", "wrong", "rule"}
# Share of a draft's characters found in one post. Calibrated on the 141 drafts of the 2026-10-21 study:
# every unposted draft scored at most 0.34 against the user's posts, and 0.45 recovers all verbatim posts
# and 23 of 36 edited ones. Heavier rewrites fall below it and count as not posted, so the posting rate
# this script reports is a lower bound.
MATCH_THRESHOLD = 0.45
PENDING_DAYS = 7


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def die(msg: str) -> None:
    print(f"ledger: {msg}", file=sys.stderr)
    sys.exit(2)


def norm(text: str) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def skill_version() -> str:
    def git(*args: str) -> str:
        out = subprocess.run(["git", "-C", str(SKILL_DIR), *args], capture_output=True, text=True)
        return out.stdout.strip() if out.returncode == 0 else ""

    sha = git("log", "-1", "--format=%h", "--", ".")
    if not sha:
        return "unknown"
    return sha + ("+dirty" if git("status", "--porcelain", "--", ".") else "")


def load(path: Path) -> dict:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def write(path: Path, data: dict) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def validate(rec: dict) -> list[str]:
    errors = []
    for key in ("repo", "pr", "head", "verdict", "drafts"):
        if key not in rec:
            errors.append(f"missing {key}")
    if "repo" in rec and not re.fullmatch(r"[\w.-]+/[\w.-]+", str(rec["repo"])):
        errors.append("repo must be owner/repo")
    if "pr" in rec and not isinstance(rec["pr"], int):
        errors.append("pr must be an integer")
    if not isinstance(rec.get("drafts", []), list):
        errors.append("drafts must be a list")
        return errors
    seen = set()
    for i, d in enumerate(rec.get("drafts", [])):
        where = f"drafts[{i}]"
        if not isinstance(d, dict):
            errors.append(f"{where} must be an object")
            continue
        if not d.get("id"):
            errors.append(f"{where} missing id")
        elif d["id"] in seen:
            errors.append(f"{where} duplicate id {d['id']}")
        seen.add(d.get("id"))
        if d.get("channel") not in ("post", "held"):
            errors.append(f"{where} channel must be post or held")
        if not norm(d.get("body", "")):
            errors.append(f"{where} empty body")
        if d.get("channel") == "held" and d.get("held_reason") not in HELD_REASONS:
            errors.append(f"{where} held_reason must be one of {sorted(HELD_REASONS)}")
        if d.get("line") is not None and not isinstance(d.get("line"), int):
            errors.append(f"{where} line must be an integer or null")
    return errors


def record_dirs(roots: list[Path]) -> list[Path]:
    dirs = []
    for root in roots:
        if root.is_dir():
            dirs.extend(p for p in sorted(root.iterdir()) if (p / "review.json").is_file())
    return dirs


def all_roots(args: argparse.Namespace) -> list[Path]:
    return [Path(args.root)] if getattr(args, "root", None) else [DEFAULT_ROOT, *EXTRA_ROOTS]


def cmd_dir(args: argparse.Namespace) -> None:
    owner, repo = args.repo.split("/", 1)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = Path(args.root or DEFAULT_ROOT) / f"{owner}-{repo}-{args.pr}-{args.head[:7]}-{stamp}"
    path.mkdir(parents=True, exist_ok=True)
    print(path)


def cmd_save(args: argparse.Namespace) -> None:
    path = Path(args.dir)
    path.mkdir(parents=True, exist_ok=True)
    target = path / "review.json"
    raw = "" if sys.stdin.isatty() else sys.stdin.read()
    if raw.strip():
        try:
            rec = json.loads(raw)
        except json.JSONDecodeError as e:
            die(f"stdin is not valid JSON: {e}")
    elif target.is_file():
        rec = load(target)
    else:
        die(f"no JSON on stdin and no {target}")
    errors = validate(rec)
    if errors:
        die("invalid review record:\n  " + "\n  ".join(errors))
    old = load(target) if target.is_file() else {}
    old_bodies = {d["id"]: d.get("first_body") or d["body"] for d in old.get("drafts", [])}
    for d in rec["drafts"]:
        first = old_bodies.get(d["id"])
        if first is not None and norm(first) != norm(d["body"]):
            d["first_body"] = first
        elif first is not None and d.get("first_body") is None:
            d.pop("first_body", None)
    rec["feedback"] = old.get("feedback", []) + [f for f in rec.get("feedback", []) if f not in old.get("feedback", [])]
    rec.setdefault("started_at", old.get("started_at") or now())
    rec["saved_at"] = now()
    rec["skill_version"] = old.get("skill_version") or skill_version()
    write(target, rec)
    posts = sum(d["channel"] == "post" for d in rec["drafts"])
    print(f"saved {target} ({posts} post, {len(rec['drafts']) - posts} held, skill {rec['skill_version']})")


def cmd_feedback(args: argparse.Namespace) -> None:
    target = Path(args.dir) / "review.json"
    if not target.is_file():
        die(f"{target} not found")
    rec = load(target)
    if args.draft and args.draft not in {d["id"] for d in rec.get("drafts", [])}:
        die(f"unknown draft {args.draft}")
    rec.setdefault("feedback", []).append({"at": now(), "action": args.action, "draft": args.draft, "text": args.text})
    write(target, rec)
    print(f"recorded {args.action} on {args.draft or 'review'} in {target}")


def cmd_find(args: argparse.Namespace) -> None:
    rows = []
    for d in record_dirs(all_roots(args)):
        rec = load(d / "review.json")
        if rec.get("repo") != args.repo or rec.get("pr") != args.pr:
            continue
        decisions = [f for f in rec.get("feedback", []) if f.get("action") in ("accept", "drop", "wrong")]
        rows.append({
            "dir": str(d),
            "head": rec.get("head"),
            "started_at": rec.get("started_at"),
            "verdict": rec.get("verdict"),
            "drafts": [{k: x.get(k) for k in ("id", "channel", "held_reason", "file", "line", "mechanism")} for x in rec.get("drafts", [])],
            "decisions": decisions,
        })
    rows.sort(key=lambda r: r.get("started_at") or "")
    print(json.dumps(rows, ensure_ascii=False, indent=2))


def gh_lines(path: str) -> list[dict]:
    out = subprocess.run(["gh", "api", "--paginate", path, "--jq", ".[]"], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"gh api {path}: {out.stderr.strip()}")
    return [json.loads(line) for line in out.stdout.splitlines() if line.strip()]


def gh_one(path: str) -> dict:
    out = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"gh api {path}: {out.stderr.strip()}")
    return json.loads(out.stdout)


def user_posts(repo: str, pr: int, login: str, since: datetime) -> list[dict]:
    posts = []
    for c in gh_lines(f"repos/{repo}/pulls/{pr}/comments"):
        posts.append({"kind": "inline", "at": c["created_at"], "login": c["user"]["login"], "body": c.get("body") or "", "path": c.get("path"), "url": c["html_url"]})
    for r in gh_lines(f"repos/{repo}/pulls/{pr}/reviews"):
        if r.get("submitted_at"):
            posts.append({"kind": "review", "at": r["submitted_at"], "login": r["user"]["login"], "body": r.get("body") or "", "path": None, "url": r["html_url"]})
    for c in gh_lines(f"repos/{repo}/issues/{pr}/comments"):
        posts.append({"kind": "issue", "at": c["created_at"], "login": c["user"]["login"], "body": c.get("body") or "", "path": None, "url": c["html_url"]})
    return [p for p in posts if p["login"] == login and norm(p["body"]) and parse_time(p["at"]) >= since]


def coverage(draft: str, post: str) -> float:
    a, b = norm(draft), norm(post)
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    blocks = difflib.SequenceMatcher(None, a, b, autojunk=False).get_matching_blocks()
    return sum(m.size for m in blocks if m.size >= 4) / len(a)


def match(drafts: list[dict], posts: list[dict]) -> dict[str, dict]:
    pairs = []
    for d in drafts:
        for i, p in enumerate(posts):
            score = coverage(d["body"], p["body"])
            # an inline post on another file is a different comment unless the text is identical
            if p["kind"] == "inline" and d.get("file") and p.get("path") and d["file"] != p["path"] and norm(d["body"]) != norm(p["body"]):
                continue
            if score >= MATCH_THRESHOLD:
                same_file = bool(d.get("file")) and d.get("file") == p.get("path")
                pairs.append((score, same_file, d["id"], i))
    pairs.sort(key=lambda x: (x[0], x[1]), reverse=True)
    taken_inline, result = set(), {}
    for score, _, did, i in pairs:
        if did in result:
            continue
        post = posts[i]
        # an inline comment answers one draft; a review body or issue comment may bundle several
        if post["kind"] == "inline":
            if i in taken_inline:
                continue
            taken_inline.add(i)
        draft = next(d for d in drafts if d["id"] == did)
        exact = norm(draft["body"]) == norm(post["body"])
        result[did] = {"match": "verbatim" if exact else "edited", "coverage": round(score, 3), "url": post["url"], "kind": post["kind"]}
    return result


def cmd_outcomes(args: argparse.Namespace) -> None:
    login = args.login or subprocess.run(["gh", "api", "user", "--jq", ".login"], capture_output=True, text=True).stdout.strip()
    if not login:
        die("cannot resolve GitHub login; pass --login")
    cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)
    rows = []
    for d in record_dirs(all_roots(args)):
        rec = load(d / "review.json")
        if args.repo and rec.get("repo") != args.repo:
            continue
        if args.pr and rec.get("pr") != args.pr:
            continue
        started = parse_time(rec.get("started_at") or rec.get("saved_at") or now())
        if started < cutoff:
            continue
        try:
            posts = user_posts(rec["repo"], rec["pr"], login, started)
            pr_state = gh_one(f"repos/{rec['repo']}/pulls/{rec['pr']}")
        except RuntimeError as e:
            print(f"skip {d.name}: {e}", file=sys.stderr)
            continue
        closed = pr_state.get("state") == "closed"
        settled = closed or bool(posts) or datetime.now(timezone.utc) - started > timedelta(days=PENDING_DAYS)
        matched = match(rec["drafts"], posts)
        drafts = {}
        for dr in rec["drafts"]:
            m = matched.get(dr["id"])
            if dr["channel"] == "post":
                status = m["match"] if m else ("not_posted" if settled else "pending")
            else:
                status = f"promoted_{m['match']}" if m else "held"
            drafts[dr["id"]] = {"status": status, **({k: m[k] for k in ("coverage", "url", "kind")} if m else {})}
        outcome = {"checked_at": now(), "login": login, "pr_state": "merged" if pr_state.get("merged_at") else pr_state.get("state"), "user_posts_since_review": len(posts), "drafts": drafts}
        write(d / "outcome.json", outcome)
        rows.append((d.name, rec, drafts))
    print_table(rows)


def tally(drafts: dict) -> dict:
    keys = ["verbatim", "edited", "not_posted", "pending", "promoted_verbatim", "promoted_edited", "held"]
    counts = dict.fromkeys(keys, 0)
    for v in drafts.values():
        counts[v["status"]] += 1
    return counts


def print_table(rows: list) -> None:
    print("record | post: verbatim/edited/not posted/pending | held: promoted/held | feedback")
    for name, rec, drafts in rows:
        c = tally(drafts)
        fb = len(rec.get("feedback", []))
        print(f"{name} | {c['verbatim']}/{c['edited']}/{c['not_posted']}/{c['pending']} | {c['promoted_verbatim'] + c['promoted_edited']}/{c['held']} | {fb}")


def cmd_stats(args: argparse.Namespace) -> None:
    cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)
    total = dict.fromkeys(["verbatim", "edited", "not_posted", "pending", "promoted_verbatim", "promoted_edited", "held"], 0)
    held_reasons: dict[str, list[int]] = {}
    feedback: dict[str, int] = {}
    reviews = 0
    for d in record_dirs(all_roots(args)):
        rec = load(d / "review.json")
        started = parse_time(rec.get("started_at") or rec.get("saved_at") or now())
        if started < cutoff or not (d / "outcome.json").is_file():
            continue
        reviews += 1
        out = load(d / "outcome.json")["drafts"]
        for k, v in tally(out).items():
            total[k] += v
        for dr in rec["drafts"]:
            if dr["channel"] == "held":
                promoted = out.get(dr["id"], {}).get("status", "").startswith("promoted")
                held_reasons.setdefault(dr["held_reason"], [0, 0])[0 if promoted else 1] += 1
        for f in rec.get("feedback", []):
            feedback[f["action"]] = feedback.get(f["action"], 0) + 1
    settled = total["verbatim"] + total["edited"] + total["not_posted"]
    print(f"reviews with outcomes in the last {args.days} days: {reviews}")
    if settled:
        print(f"recommended drafts settled: {settled}; posted unchanged {total['verbatim']} ({total['verbatim'] / settled:.0%}), posted edited {total['edited']} ({total['edited'] / settled:.0%}), not posted {total['not_posted']} ({total['not_posted'] / settled:.0%}); pending {total['pending']}")
    held = total["promoted_verbatim"] + total["promoted_edited"] + total["held"]
    if held:
        print(f"held drafts: {held}; promoted by the user {total['promoted_verbatim'] + total['promoted_edited']}")
        for reason, (promoted, kept) in sorted(held_reasons.items()):
            print(f"  {reason}: promoted {promoted}, kept held {kept}")
    if feedback:
        print("session feedback: " + ", ".join(f"{k} {v}" for k, v in sorted(feedback.items())))


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("dir", help="create and print a new record directory")
    s.add_argument("--repo", required=True, help="owner/repo")
    s.add_argument("--pr", required=True, type=int)
    s.add_argument("--head", required=True)
    s.add_argument("--root", help=f"default {DEFAULT_ROOT}")
    s.set_defaults(func=cmd_dir)

    s = sub.add_parser("save", help="validate and write <dir>/review.json from stdin (or re-validate the existing file)")
    s.add_argument("dir")
    s.set_defaults(func=cmd_save)

    s = sub.add_parser("feedback", help="append the user's reaction to a review or one draft")
    s.add_argument("dir")
    s.add_argument("--action", required=True, choices=sorted(FEEDBACK_ACTIONS))
    s.add_argument("--draft", help="draft id, omitted for review-level feedback")
    s.add_argument("--text", required=True, help="the user's words, verbatim")
    s.set_defaults(func=cmd_feedback)

    s = sub.add_parser("find", help="list earlier records for one PR, with the user's recorded decisions")
    s.add_argument("--repo", required=True)
    s.add_argument("--pr", required=True, type=int)
    s.add_argument("--root")
    s.set_defaults(func=cmd_find)

    s = sub.add_parser("outcomes", help="match drafts against what the user posted on GitHub and write outcome.json")
    s.add_argument("--repo")
    s.add_argument("--pr", type=int)
    s.add_argument("--days", type=int, default=30, help="only records started in the last N days (default 30)")
    s.add_argument("--login", help="GitHub login whose posts count (default: gh api user)")
    s.add_argument("--root")
    s.set_defaults(func=cmd_outcomes)

    s = sub.add_parser("stats", help="aggregate posting, editing and held-promotion rates from outcome.json files")
    s.add_argument("--days", type=int, default=90)
    s.add_argument("--root")
    s.set_defaults(func=cmd_stats)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
