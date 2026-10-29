#!/usr/bin/env python3
"""GitHub side of the slack-pr-review lifecycle: read the user's review threads, build and check the payload the user is asked to approve, and post exactly that payload once they reply.

A payload is one JSON file holding everything a single post would send:

  {"repo": "owner/repo", "pr": 123, "kind": "first_review" | "fixcheck", "commit_id": "<sha>", "base": "main",
   "verdict": "approve" | "changes" | null,
   "items": [
     {"n": 1, "type": "comment", "path": "src/x.py", "line": 12, "body": "...", "blocking": true, "draft": "D1"},
     {"n": 2, "type": "file_comment", "path": "src/y.py", "body": "..."},   a comment on a changed file whose line is outside the diff
     {"n": 3, "type": "pr_comment", "body": "..."},                  one PR conversation comment (no file, or a file the PR does not change)
     {"n": 4, "type": "reply", "in_reply_to": 456, "body": "...", "thread_url": "..."},
     {"n": 1, "type": "approve", "body": "LGTM!"}                    an approval is always the only item
   ]}

Every item is its own comment and nothing is ever written into a review body: the user wants each request posted separately. `post` sends the line comments together as one COMMENT review with no body at commit_id (falling back to one review comment each if GitHub insists on a body), each file comment and PR comment on its own, each reply to its thread, and an approval as an APPROVE review whose body is the approval text. It posts only when the PR is open and, for an approval, only while the head is still commit_id. A legacy "body" item is treated as a pr_comment. It needs --approval naming the user's Slack reply that allowed it, records every call in posted.json next to the payload, and skips items already posted, so a retry never posts twice. Runs on the macOS system Python (3.9).
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

TYPES = ("comment", "file_comment", "pr_comment", "reply", "approve")
META_QUERY = """
query($owner: String!, $repo: String!, $n: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $n) {
      state isDraft headRefOid baseRefName url title author { login }
      reviewRequests(first: 50) { nodes { requestedReviewer { ... on User { login } } } }
      reviews(last: 100) { nodes { databaseId state author { login } commit { oid } submittedAt url body } }
      commits(last: 1) { nodes { commit { oid committedDate } } }
      comments(last: 100) { nodes { databaseId author { login } body createdAt url } }
    }
  }
}
"""
THREADS_QUERY = """
query($owner: String!, $repo: String!, $n: Int!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $n) {
      reviewThreads(first: 50, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          isResolved isOutdated path line originalLine
          comments(first: 100) { nodes { databaseId author { login } body createdAt url originalCommit { oid } } }
        }
      }
    }
  }
}
"""


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def gh(args, stdin=None):
    result = subprocess.run(["gh"] + args, input=stdin, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError("gh {}: {}".format(" ".join(args[:3]), (result.stderr or result.stdout).strip()[:500]))
    return result.stdout


def graphql(query, **variables):
    args = ["api", "graphql", "-f", "query=" + query]
    for key, value in variables.items():
        if value is None:
            continue
        args += ["-F" if isinstance(value, int) else "-f", "{}={}".format(key, value)]
    data = json.loads(gh(args))
    if data.get("errors"):
        raise RuntimeError("graphql: " + json.dumps(data["errors"])[:500])
    return data["data"]


def split_repo(repo):
    owner, name = repo.split("/", 1)
    return owner, name


def login_of(node):
    return (node.get("author") or {}).get("login") or "ghost"


def cmd_threads(args):
    """Print the PR's state and every review thread the user started, with the replies under it."""
    owner, name = split_repo(args.repo)
    pr = graphql(META_QUERY, owner=owner, repo=name, n=args.pr)["repository"]["pullRequest"]
    threads, cursor = [], None
    while True:
        page = graphql(THREADS_QUERY, owner=owner, repo=name, n=args.pr, cursor=cursor)["repository"]["pullRequest"]["reviewThreads"]
        for node in page["nodes"]:
            comments = node["comments"]["nodes"]
            if not comments or login_of(comments[0]) != args.login:
                continue
            root = comments[0]
            threads.append({
                "root_id": root["databaseId"], "url": root["url"], "path": node["path"], "line": node["line"], "original_line": node["originalLine"],
                "resolved": node["isResolved"], "outdated": node["isOutdated"], "commit": (root.get("originalCommit") or {}).get("oid"),
                "body": root["body"], "created_at": root["createdAt"],
                "replies": [{"id": c["databaseId"], "author": login_of(c), "body": c["body"], "created_at": c["createdAt"], "url": c["url"]} for c in comments[1:]],
            })
        if not page["pageInfo"]["hasNextPage"]:
            break
        cursor = page["pageInfo"]["endCursor"]
    mine = [r for r in pr["reviews"]["nodes"] if login_of(r) == args.login]
    submitted = [r["submittedAt"] for r in mine if r.get("submittedAt")]
    first_review_at = min(submitted) if submitted else None
    conversation = [{"id": c["databaseId"], "author": login_of(c), "body": c["body"], "created_at": c["createdAt"], "url": c["url"]}
                    for c in pr["comments"]["nodes"] if login_of(c) != args.login and (first_review_at is None or c["createdAt"] > first_review_at)]
    others = [x["created_at"] for t in threads for x in t["replies"] if x["author"] != args.login] + [c["created_at"] for c in conversation]
    head_commit = (pr["commits"]["nodes"] or [{}])[0].get("commit") or {}
    out = {
        "repo": args.repo, "pr": args.pr, "fetched_at": now_iso(), "login": args.login, "url": pr["url"], "title": pr["title"],
        "state": pr["state"], "draft": pr["isDraft"], "head": pr["headRefOid"], "base": pr["baseRefName"], "author": login_of(pr),
        "head_committed_at": head_commit.get("committedDate"),
        "review_requested": any(((n.get("requestedReviewer") or {}).get("login")) == args.login for n in pr["reviewRequests"]["nodes"]),
        "reviews": [{"id": r["databaseId"], "state": r["state"], "commit": (r.get("commit") or {}).get("oid"), "submitted_at": r["submittedAt"], "url": r["url"]} for r in mine],
        "threads": threads, "conversation": conversation,
        "last_other_activity": max(others + [head_commit.get("committedDate") or ""]) or None,
    }
    text = json.dumps(out, ensure_ascii=False, indent=1)
    if args.out:
        with open(args.out, "w") as f:
            f.write(text + "\n")
        print("{}: {} threads, {} unresolved, head {}, review requested {}".format(args.out, len(threads), sum(not t["resolved"] for t in threads), out["head"][:7], out["review_requested"]))
    else:
        print(text)
    return 0


def diff_lines(repo, base, commit):
    """Map each changed file to the right-side lines a review comment can anchor to at commit (added and context lines of the PR diff)."""
    data = json.loads(gh(["api", "repos/{}/compare/{}...{}".format(repo, base, commit)]))
    lines = {}
    for f in data.get("files", []):
        patch = f.get("patch")
        if patch is None:
            lines[f["filename"]] = None
            continue
        found, new = set(), None
        for row in patch.split("\n"):
            m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", row)
            if m:
                new = int(m.group(1))
                continue
            if new is None or row.startswith("-") or row.startswith("\\"):
                continue
            found.add(new)
            new += 1
        lines[f["filename"]] = found
    return lines


def load_payload(path):
    with open(path) as f:
        payload = json.load(f)
    for item in payload.get("items", []):
        if item.get("type") == "body":
            item["type"] = "pr_comment"
    return payload


def save_payload(path, payload):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(payload, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.replace(tmp, path)


def validate(payload):
    errors = []
    for key in ("repo", "pr", "kind", "commit_id", "items"):
        if key not in payload:
            errors.append("missing " + key)
    items = payload.get("items") or []
    numbers = [i.get("n") for i in items]
    if len(set(numbers)) != len(numbers) or not all(isinstance(n, int) for n in numbers):
        errors.append("item numbers must be distinct integers")
    for item in items:
        where = "item {}".format(item.get("n"))
        kind = item.get("type")
        if kind not in TYPES:
            errors.append("{}: type must be one of {}".format(where, ", ".join(TYPES)))
        if not (item.get("body") or "").strip():
            errors.append(where + ": empty body")
        if kind == "comment" and not (item.get("path") and isinstance(item.get("line"), int)):
            errors.append(where + ": a comment needs path and an integer line")
        if kind == "file_comment" and not item.get("path"):
            errors.append(where + ": a file comment needs path")
        if kind == "reply" and not isinstance(item.get("in_reply_to"), int):
            errors.append(where + ": a reply needs the integer in_reply_to of the thread's first comment")
    if any(i.get("type") == "approve" for i in items) and len(items) != 1:
        errors.append("an approval must be the payload's only item")
    return errors


def cmd_payload(args):
    """Build the first-review payload from a pr-review ledger record (its post drafts), or an approval when it has none."""
    with open(args.ledger) as f:
        rec = json.load(f)
    drafts = [d for d in rec.get("drafts", []) if d.get("channel") == "post"]
    items = []
    for d in drafts:
        item = {"n": len(items) + 1, "body": d["body"], "blocking": d.get("blocking"), "draft": d.get("id")}
        if d.get("file") and isinstance(d.get("line"), int):
            item.update({"type": "comment", "path": d["file"], "line": d["line"]})
        elif d.get("file"):
            item.update({"type": "file_comment", "path": d["file"]})
        else:
            item["type"] = "pr_comment"
        items.append(item)
    if not items:
        items = [{"n": 1, "type": "approve", "body": args.approve_body}]
    payload = {"repo": rec["repo"], "pr": int(rec["pr"]), "kind": "first_review", "commit_id": rec["head"], "base": rec.get("base") or args.base,
               "verdict": "approve" if items[0]["type"] == "approve" else "changes", "source": os.path.abspath(args.ledger), "items": items}
    save_payload(args.out, payload)
    print("{}: {} items ({})".format(args.out, len(items), ", ".join(sorted({i["type"] for i in items}))))
    return 0


def cmd_check(args):
    """Validate a payload. A comment whose line is outside the PR diff at commit_id becomes a file comment when the PR changes that file, else a PR comment; either way its text names the file and line."""
    payload = load_payload(args.payload)
    errors = validate(payload)
    if errors:
        print("invalid payload:\n  " + "\n  ".join(errors))
        return 1
    comments = [i for i in payload["items"] if i["type"] == "comment"]
    moved = []
    if comments:
        lines = diff_lines(payload["repo"], payload.get("base") or "main", payload["commit_id"])
        for item in comments:
            anchors = lines.get(item["path"], set())
            if anchors is None:
                continue
            if item["line"] not in anchors:
                where = "`{}:{}`".format(item["path"], item["line"])
                if where not in item["body"] and "`{}`".format(item["path"]) not in item["body"]:
                    item["body"] = "{}: {}".format(where, item["body"])
                if item["path"] in lines:
                    item["type"] = "file_comment"
                    item.pop("line")
                    moved.append("{} (file comment)".format(item["n"]))
                else:
                    item["type"] = "pr_comment"
                    item.pop("path")
                    item.pop("line")
                    moved.append("{} (PR comment)".format(item["n"]))
    save_payload(args.payload, payload)
    print("ok: {} items{}".format(len(payload["items"]), "; line outside the diff, so posted separately as: " + ", ".join(moved) if moved else ""))
    return 0


def render_item(item, payload):
    blocking = {True: "blocking", False: "non-blocking"}.get(item.get("blocking"))
    if item["type"] == "approve":
        head = "**{}. Approve** at `{}`".format(item["n"], payload["commit_id"][:7])
    elif item["type"] == "comment":
        head = "**{}. {}** `{}:{}`".format(item["n"], blocking or "comment", item["path"], item["line"])
    elif item["type"] == "file_comment":
        head = "**{}. {}** `{}` (file comment)".format(item["n"], blocking or "comment", item["path"])
    elif item["type"] == "reply":
        where = item.get("thread_url")
        head = "**{}. Reply** {}".format(item["n"], "in [this thread]({})".format(where) if where else "to comment {}".format(item["in_reply_to"]))
    else:
        head = "**{}. PR comment**{}".format(item["n"], " ({})".format(blocking) if blocking else "")
    return head + "\n\n" + item["body"]


def cmd_render(args):
    """Print each item (or one with --item) as the Slack markdown the user is shown, as a JSON list of strings."""
    payload = load_payload(args.payload)
    items = [i for i in payload["items"] if args.item is None or i["n"] == args.item]
    if args.item is not None and not items:
        sys.exit("no item {}".format(args.item))
    print(json.dumps([render_item(i, payload) for i in items], ensure_ascii=False))
    return 0


def posted_path(payload_path):
    return os.path.join(os.path.dirname(os.path.abspath(payload_path)), "posted.json")


def load_posted(payload_path):
    try:
        with open(posted_path(payload_path)) as f:
            return json.load(f)
    except FileNotFoundError:
        return {"calls": []}


def cmd_edit(args):
    """Replace one item's body with the text on stdin, before it is posted."""
    payload = load_payload(args.payload)
    posted = {c["n"] for c in load_posted(args.payload)["calls"] if c.get("ok")}
    text = sys.stdin.read().strip()
    if not text:
        sys.exit("empty body")
    for item in payload["items"]:
        if item["n"] == args.n:
            if item["n"] in posted:
                sys.exit("item {} is already posted".format(args.n))
            item.setdefault("edits", []).append({"at": now_iso(), "previous": item["body"]})
            item["body"] = text
            save_payload(args.payload, payload)
            print(json.dumps([render_item(item, payload)], ensure_ascii=False))
            return 0
    sys.exit("no item {}".format(args.n))


def digest(payload):
    stripped = {k: v for k, v in payload.items() if k != "source"}
    return hashlib.sha256(json.dumps(stripped, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]


def cmd_post(args):
    """Post the selected items (default all) as the user, after their Slack reply allowed it."""
    payload = load_payload(args.payload)
    errors = validate(payload)
    if errors:
        print("invalid payload:\n  " + "\n  ".join(errors))
        return 1
    chosen = set(args.select) if args.select else {i["n"] for i in payload["items"]}
    unknown = chosen - {i["n"] for i in payload["items"]}
    if unknown:
        print("unknown items: " + ", ".join(map(str, sorted(unknown))))
        return 1
    record = load_posted(args.payload)
    done = {c["n"] for c in record["calls"] if c.get("ok")}
    items = [i for i in payload["items"] if i["n"] in chosen and i["n"] not in done]
    repo, number = payload["repo"], payload["pr"]
    pr = json.loads(gh(["api", "repos/{}/pulls/{}".format(repo, number)]))
    if pr["state"] != "open":
        print("refused: the PR is {}".format("merged" if pr.get("merged") else pr["state"]))
        return 3
    if any(i["type"] == "approve" for i in items) and pr["head"]["sha"] != payload["commit_id"]:
        print("refused: the head moved from {} to {} since the check; run a new fix check first".format(payload["commit_id"][:7], pr["head"]["sha"][:7]))
        return 4
    calls = []
    line_items = [i for i in items if i["type"] == "comment"]
    if line_items:
        comments = [{"path": i["path"], "line": i["line"], "side": "RIGHT", "body": i["body"]} for i in line_items]
        calls.append(([i["n"] for i in line_items], "repos/{}/pulls/{}/reviews".format(repo, number), {"commit_id": payload["commit_id"], "event": "COMMENT", "comments": comments}))
    for i in items:
        if i["type"] == "file_comment":
            calls.append(([i["n"]], "repos/{}/pulls/{}/comments".format(repo, number), {"commit_id": payload["commit_id"], "path": i["path"], "subject_type": "file", "body": i["body"]}))
        elif i["type"] == "pr_comment":
            calls.append(([i["n"]], "repos/{}/issues/{}/comments".format(repo, number), {"body": i["body"]}))
        elif i["type"] == "reply":
            calls.append(([i["n"]], "repos/{}/pulls/{}/comments/{}/replies".format(repo, number, i["in_reply_to"]), {"body": i["body"]}))
        elif i["type"] == "approve":
            calls.append(([i["n"]], "repos/{}/pulls/{}/reviews".format(repo, number), {"commit_id": payload["commit_id"], "event": "APPROVE", "body": i["body"]}))
    if args.dry_run:
        print(json.dumps([{"items": n, "POST": endpoint, "json": body} for n, endpoint, body in calls], ensure_ascii=False, indent=1))
        return 0
    if not args.approval:
        print("refused: --approval must name the user's Slack reply that allowed this post")
        return 1
    results, failed = [], False

    def save_record():
        with open(posted_path(args.payload), "w") as f:
            json.dump(record, f, ensure_ascii=False, indent=1)
            f.write("\n")

    def send(numbers, endpoint, body):
        """POST one call and record its items as posted or failed; return False when it failed."""
        try:
            response = json.loads(gh(["api", "-X", "POST", endpoint, "--input", "-"], stdin=json.dumps(body)))
        except RuntimeError as exc:
            for n in numbers:
                record["calls"].append({"n": n, "ok": False, "endpoint": endpoint, "error": str(exc), "at": now_iso(), "approval": args.approval})
            results.append({"items": numbers, "error": str(exc)})
            save_record()
            return False
        url = response.get("html_url") or response.get("_links", {}).get("html", {}).get("href")
        for n in numbers:
            record["calls"].append({"n": n, "ok": True, "endpoint": endpoint, "id": response.get("id"), "url": url, "at": now_iso(), "approval": args.approval, "payload": digest(payload)})
        results.append({"items": numbers, "url": url})
        save_record()
        return True

    for numbers, endpoint, body in calls:
        is_bodyless_review = endpoint.endswith("/reviews") and body.get("event") == "COMMENT"
        if is_bodyless_review:
            try:
                response = json.loads(gh(["api", "-X", "POST", endpoint, "--input", "-"], stdin=json.dumps(body)))
            except RuntimeError as exc:
                if "body" not in str(exc).lower():
                    for n in numbers:
                        record["calls"].append({"n": n, "ok": False, "endpoint": endpoint, "error": str(exc), "at": now_iso(), "approval": args.approval})
                    results.append({"items": numbers, "error": str(exc)})
                    save_record()
                    failed = True
                    continue
                # GitHub wanted a review body: post the same line comments one at a time, still with no body.
                single = "repos/{}/pulls/{}/comments".format(repo, number)
                for n, comment in zip(numbers, body["comments"]):
                    failed = not send([n], single, dict(comment, commit_id=body["commit_id"])) or failed
                continue
            url = response.get("html_url") or response.get("_links", {}).get("html", {}).get("href")
            for n in numbers:
                record["calls"].append({"n": n, "ok": True, "endpoint": endpoint, "id": response.get("id"), "url": url, "at": now_iso(), "approval": args.approval, "payload": digest(payload)})
            results.append({"items": numbers, "url": url})
            save_record()
        else:
            failed = not send(numbers, endpoint, body) or failed
    print(json.dumps({"posted": results, "skipped_already_posted": sorted(chosen & done)}, ensure_ascii=False))
    return 2 if failed else 0


def main():
    parser = argparse.ArgumentParser(description="GitHub side of the slack-pr-review lifecycle.")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("threads", help="print the PR state and the review threads LOGIN started, with replies")
    p.add_argument("repo")
    p.add_argument("pr", type=int)
    p.add_argument("--login", required=True)
    p.add_argument("--out", help="write the JSON to this file and print a one-line summary")
    p.set_defaults(func=cmd_threads)

    p = sub.add_parser("payload", help="build the first-review payload from a ledger review.json")
    p.add_argument("ledger")
    p.add_argument("--out", required=True)
    p.add_argument("--base", default="main")
    p.add_argument("--approve-body", default="LGTM!")
    p.set_defaults(func=cmd_payload)

    p = sub.add_parser("check", help="validate a payload and move out-of-diff comments into the review body")
    p.add_argument("payload")
    p.set_defaults(func=cmd_check)

    p = sub.add_parser("render", help="print the items as Slack markdown, a JSON list of strings")
    p.add_argument("payload")
    p.add_argument("--item", type=int)
    p.set_defaults(func=cmd_render)

    p = sub.add_parser("edit", help="replace item N's body with the text on stdin")
    p.add_argument("payload")
    p.add_argument("n", type=int)
    p.set_defaults(func=cmd_edit)

    p = sub.add_parser("post", help="post the selected items as the user; exit 3 closed PR, 4 head moved before an approval, 2 a call failed")
    p.add_argument("payload")
    p.add_argument("--select", type=int, nargs="*", help="item numbers to post (default all)")
    p.add_argument("--approval", help="the Slack reply that allowed the post (permalink or channel/ts)")
    p.add_argument("--dry-run", action="store_true", help="print the API calls without sending them")
    p.set_defaults(func=cmd_post)

    args = parser.parse_args()
    try:
        return args.func(args)
    except RuntimeError as exc:
        print(str(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
