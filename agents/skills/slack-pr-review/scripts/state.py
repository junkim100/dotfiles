#!/usr/bin/env python3
"""Durable state for the slack-pr-review skill.

Every write takes an exclusive lock and replaces state.json atomically, so an interrupted tick never leaves a half-written file and two sessions never interleave updates. JSON payloads arrive on stdin, so Slack text containing quotes or Korean needs no shell escaping. Runs on the macOS system Python (3.9), so it avoids newer syntax.
"""

import argparse
import fcntl
import json
import os
import sys
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone

HOME = os.environ.get("SLACK_PR_REVIEW_HOME") or os.path.expanduser("~/.local/state/slack-pr-review")
STATE = os.path.join(HOME, "state.json")
LOCK = os.path.join(HOME, "state.lock")
EMPTY = {"watermark": None, "owner": None, "run": None, "repos": {}, "messages": {}, "reviews": {}, "harness_limits": {}, "coordinator": None}
HARNESSES = ("codex", "claude")
# Statuses that hold or wait for a worker; a tick keeps its claim while any review is in one.
REVIEW_ACTIVE = ("queued", "running", "gate_flat", "fix_queued", "fix_running")
# Statuses of a review that is still open in its lifecycle: waiting for the user's post decision, or tracked until the user approves.
REVIEW_TRACKED = ("awaiting_post", "tracking", "fix_queued", "fix_running")


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def age_minutes(iso):
    then = datetime.strptime(iso, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - then).total_seconds() / 60


def load():
    try:
        with open(STATE) as f:
            data = json.load(f)
    except FileNotFoundError:
        data = {}
    for key, value in EMPTY.items():
        data.setdefault(key, json.loads(json.dumps(value)))
    return data


@contextmanager
def locked():
    os.makedirs(HOME, exist_ok=True)
    with open(LOCK, "a") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        data = load()
        yield data
        fd, tmp = tempfile.mkstemp(dir=HOME, prefix=".state.", suffix=".json")
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.write("\n")
        os.replace(tmp, STATE)


def read_stdin_json(optional=False):
    raw = "" if sys.stdin.isatty() else sys.stdin.read()
    if not raw.strip():
        if optional:
            return {}
        sys.exit("expected a JSON object on stdin")
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        sys.exit("stdin must be a JSON object")
    return payload


def merge(target, fields):
    """Merge fields into target, recursing into nested objects so a partial update keeps sibling keys."""
    for key, value in fields.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            merge(target[key], value)
        else:
            target[key] = value


def emit(value):
    print(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))


def cmd_claim(args):
    with locked() as data:
        owner = data["owner"]
        mine = owner and owner.get("terminal") == args.terminal
        stale = owner and age_minutes(owner["heartbeat"]) > args.stale_minutes
        if owner and not (mine or stale or args.force):
            emit(owner)
            return 3
        data["owner"] = {"terminal": args.terminal, "heartbeat": now_iso()}
    print("claimed")
    return 0


def cmd_release(args):
    with locked() as data:
        owner = data["owner"]
        if owner and owner.get("terminal") == args.terminal:
            data["owner"] = None
            print("released")
        else:
            print("not the owner; nothing released")
    return 0


def cmd_watermark(args):
    if args.set is None:
        print(load()["watermark"] or "")
        return 0
    with locked() as data:
        current = data["watermark"]
        if current is None or args.force or float(args.set) > float(current):
            data["watermark"] = args.set
        print(data["watermark"])
    return 0


def cmd_seen(args):
    messages = load()["messages"]
    for key in args.keys:
        if key not in messages:
            print(key)
    return 0


def cmd_message(args):
    record = read_stdin_json()
    with locked() as data:
        if args.merge:
            if args.key not in data["messages"]:
                sys.exit("no message record " + args.key)
            merge(data["messages"][args.key], record)
        else:
            record["triaged_at"] = now_iso()
            data["messages"][args.key] = record
    return 0


def cmd_asks(args):
    """Print every DM question still waiting for the user's answer: unclear requests (message) and post decisions (review)."""
    data = load()
    for key, record in sorted(data["messages"].items(), key=lambda item: item[1].get("ts", "")):
        ask = record.get("ask") or {}
        if ask.get("status") == "asked":
            print("\t".join(["message", key, ask.get("channel", ""), ask.get("ts", ""), ask.get("asked_at", ""), ",".join(record.get("prs") or []) or "-"]))
    for pr, record in sorted(data["reviews"].items(), key=lambda item: (item[1].get("ask") or {}).get("asked_at", "")):
        ask = record.get("ask") or {}
        if ask.get("status") == "asked":
            print("\t".join(["review", pr, ask.get("channel", ""), ask.get("ts", ""), ask.get("asked_at", ""), ask.get("kind", "-")]))
    return 0


def cmd_signal(args):
    """Append a signal that the author may have addressed the comments (JSON on stdin, deduped by ref), or print the pending ones with --pending."""
    with locked() as data:
        record = data["reviews"].get(args.pr)
        if record is None:
            sys.exit("no review record " + args.pr)
        watch = record.setdefault("watch", {})
        pending = watch.setdefault("signals", [])
        if args.pending:
            emit(pending)
            return 0
        signal = read_stdin_json()
        refs = {s.get("ref") for s in pending} | set(watch.get("taken_refs", []))
        if signal.get("ref") in refs:
            print("duplicate")
            return 0
        signal.setdefault("recorded_at", now_iso())
        pending.append(signal)
        record["updated_at"] = now_iso()
        print("recorded")
    return 0


def cmd_ack(args):
    """Track the user's replies a review acknowledges with a reaction: add one, mark its reaction state, or list them."""
    with locked() as data:
        record = data["reviews"].get(args.pr)
        if record is None:
            sys.exit("no review record " + args.pr)
        acks = record.setdefault("acks", [])
        if args.add:
            if not any(a["ref"] == args.add for a in acks):
                acks.append({"ref": args.add, "state": "pending", "added_at": now_iso()})
            record["updated_at"] = now_iso()
        elif args.mark:
            ref, state = args.mark
            for a in acks:
                if a["ref"] == ref:
                    a["state"] = state
                    a["marked_at"] = now_iso()
                    break
            else:
                sys.exit("no ack " + ref)
        for a in acks:
            channel, ts = a["ref"].split("/", 1)
            print("\t".join([channel, ts, a["state"]]))
    return 0


def cmd_fix(args):
    """Open the next fix check of a review (--new prints its folder) or merge fields (JSON on stdin) into fix check N."""
    with locked() as data:
        record = data["reviews"].get(args.pr)
        if record is None or not record.get("report_dir"):
            sys.exit("no review record with a report_dir for " + args.pr)
        fixes = record.setdefault("fixes", [])
        if args.new:
            n = len(fixes) + 1
            folder = os.path.join(record["report_dir"], "fix-{}".format(n))
            os.makedirs(folder, exist_ok=True)
            fields = read_stdin_json(optional=True)
            taken = [s.get("ref") for s in fields.get("signals", []) if s.get("ref")]
            watch = record.setdefault("watch", {})
            watch["taken_refs"] = (watch.get("taken_refs") or []) + taken
            watch["signals"] = [s for s in watch.get("signals", []) if s.get("ref") not in taken]
            entry = {"n": n, "dir": folder, "created_at": now_iso()}
            merge(entry, fields)
            fixes.append(entry)
            record["updated_at"] = now_iso()
            print(folder)
            return 0
        if args.set is None or not 1 <= args.set <= len(fixes):
            sys.exit("give --new or --set <existing fix number>")
        merge(fixes[args.set - 1], read_stdin_json())
        record["updated_at"] = now_iso()
    return 0


def cmd_review(args):
    fields = read_stdin_json(optional=True)
    with locked() as data:
        reviews = data["reviews"]
        record = reviews.get(args.pr)
        if args.new_round and record:
            history = record.pop("history", [])
            history.append(record)
            record = {"history": history}
        record = record or {"history": []}
        merge(record, fields)
        for key in args.add_request or []:
            requests = record.setdefault("requests", [])
            if key not in requests:
                requests.append(key)
        record["updated_at"] = now_iso()
        reviews[args.pr] = record
    emit(record)
    return 0


def cmd_get(args):
    emit(load()["reviews"].get(args.pr))
    return 0


def cmd_list(args):
    for pr, record in sorted(load()["reviews"].items(), key=lambda item: item[1].get("updated_at", "")):
        status = record.get("status", "")
        if args.status and status not in args.status:
            continue
        if args.active and status not in REVIEW_ACTIVE:
            continue
        if args.tracked and status not in REVIEW_TRACKED:
            continue
        if args.days is not None and age_minutes(record["updated_at"]) > args.days * 24 * 60:
            continue
        dispatch = record.get("dispatch") or "-"
        if isinstance(dispatch, list):
            dispatch = ",".join(dispatch) or "-"
        cols = [pr, status, (record.get("head") or "")[:7], dispatch, record.get("report_dir") or "-"]
        print("\t".join(cols))
    return 0


def cmd_run(args):
    if args.set is None and not args.clear:
        print(load()["run"] or "")
        return 0
    with locked() as data:
        data["run"] = None if args.clear else args.set
    return 0


def cmd_repo(args):
    if args.set is None:
        print(load()["repos"].get(args.repo, ""))
        return 0
    with locked() as data:
        data["repos"][args.repo] = args.set
    return 0


def cmd_report_dir(args):
    owner_repo, number = args.pr.split("#", 1)
    name = "{}-{}-{}".format(owner_repo.replace("/", "-"), number, args.head[:7])
    path = os.path.join(HOME, "reviews", name)
    if not args.dry:
        os.makedirs(path, exist_ok=True)
    print(path)
    return 0


def cmd_coordinator(args):
    if args.set is None and not args.clear:
        print(load()["coordinator"] or "")
        return 0
    with locked() as data:
        data["coordinator"] = None if args.clear else args.set
    return 0


def cmd_harness(args):
    """Print which harnesses are usable now, or record that one is out of usage credits until a time."""
    if args.name is None:
        limits = load()["harness_limits"]
        now = now_iso()
        status = {h: (limits.get(h) if limits.get(h) and limits[h]["until"] > now else None) for h in HARNESSES}
        if args.available:
            for h in HARNESSES:
                if status[h] is None:
                    print(h)
        else:
            emit(status)
        return 0
    if args.name not in HARNESSES:
        sys.exit("harness must be one of " + ", ".join(HARNESSES))
    with locked() as data:
        if args.clear:
            data["harness_limits"].pop(args.name, None)
        elif args.unavailable_until:
            data["harness_limits"][args.name] = {"until": args.unavailable_until, "reason": args.reason or "", "recorded_at": now_iso()}
        else:
            sys.exit("give --unavailable-until or --clear")
    return 0


def cmd_show(args):
    emit(load())
    return 0


def main():
    parser = argparse.ArgumentParser(description="Durable state for the slack-pr-review skill.")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("claim", help="claim or refresh loop ownership; exit 3 when another live session owns it")
    p.add_argument("--terminal", required=True)
    p.add_argument("--stale-minutes", type=float, default=30)
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_claim)

    p = sub.add_parser("asks", help="list DM questions still waiting for the user's answer: kind (message or review), key or PR, DM channel, DM ts, asked_at, PRs or ask kind")
    p.set_defaults(func=cmd_asks)

    p = sub.add_parser("signal", help="record a fix-ready signal for a tracked review (JSON on stdin with kind, ref, at, text), or print the pending ones with --pending; fix --new consumes the signals it lists")
    p.add_argument("pr")
    p.add_argument("--pending", action="store_true")
    p.set_defaults(func=cmd_signal)

    p = sub.add_parser("ack", help="list a review's acknowledged replies (channel, ts, reaction state), --add <channel>/<ts>, or --mark <channel>/<ts> <loading|done|failed>")
    p.add_argument("pr")
    p.add_argument("--add")
    p.add_argument("--mark", nargs=2, metavar=("REF", "STATE"))
    p.set_defaults(func=cmd_ack)

    p = sub.add_parser("fix", help="open the next fix check of a review and print its folder (--new, optional JSON on stdin; its signals leave the pending list) or update fix check N (--set N, JSON on stdin)")
    p.add_argument("pr")
    p.add_argument("--new", action="store_true")
    p.add_argument("--set", type=int)
    p.set_defaults(func=cmd_fix)

    p = sub.add_parser("release", help="drop the loop claim when this session holds it")
    p.add_argument("--terminal", required=True)
    p.set_defaults(func=cmd_release)

    p = sub.add_parser("watermark", help="print the Slack ts watermark, or move it forward with --set")
    p.add_argument("--set")
    p.add_argument("--force", action="store_true", help="allow moving the watermark backwards")
    p.set_defaults(func=cmd_watermark)

    p = sub.add_parser("seen", help="print the given message keys that have not been triaged yet")
    p.add_argument("keys", nargs="*")
    p.set_defaults(func=cmd_seen)

    p = sub.add_parser("message", help="store a triage record (JSON on stdin) under <channel_id>/<message_ts>; --merge updates fields of an existing one")
    p.add_argument("key")
    p.add_argument("--merge", action="store_true")
    p.set_defaults(func=cmd_message)

    p = sub.add_parser("review", help="merge fields (JSON on stdin) into the review record of owner/repo#N")
    p.add_argument("pr")
    p.add_argument("--new-round", action="store_true", help="archive the current record into history first")
    p.add_argument("--add-request", action="append", help="append a message key to requests unless already present")
    p.set_defaults(func=cmd_review)

    p = sub.add_parser("get", help="print the review record of owner/repo#N")
    p.add_argument("pr")
    p.set_defaults(func=cmd_get)

    p = sub.add_parser("list", help="list review records (PR, status, head, dispatch, report dir), oldest update first")
    p.add_argument("--status", nargs="*")
    p.add_argument("--active", action="store_true", help="only reviews that hold or wait for a worker: " + ", ".join(REVIEW_ACTIVE))
    p.add_argument("--tracked", action="store_true", help="only reviews still open in their lifecycle: " + ", ".join(REVIEW_TRACKED))
    p.add_argument("--days", type=float, help="only reviews updated within this many days")
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("run", help="print, set, or clear the bound Orca Run id")
    p.add_argument("--set")
    p.add_argument("--clear", action="store_true")
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("repo", help="print or set the local clone path for owner/repo")
    p.add_argument("repo")
    p.add_argument("--set")
    p.set_defaults(func=cmd_repo)

    p = sub.add_parser("report-dir", help="create and print the report directory for owner/repo#N at a head SHA")
    p.add_argument("pr")
    p.add_argument("head")
    p.add_argument("--dry", action="store_true", help="print the path without creating it")
    p.set_defaults(func=cmd_report_dir)

    p = sub.add_parser("coordinator", help="print, set, or clear the loop's own Orca coordinator terminal handle")
    p.add_argument("--set")
    p.add_argument("--clear", action="store_true")
    p.set_defaults(func=cmd_coordinator)

    p = sub.add_parser("harness", help="print harness availability, list usable harnesses with --available, or mark one out of usage credits")
    p.add_argument("name", nargs="?")
    p.add_argument("--available", action="store_true", help="print the harnesses usable now, one per line")
    p.add_argument("--unavailable-until", help="ISO 8601 UTC time when the usage limit resets")
    p.add_argument("--reason", help="the limit message, one line")
    p.add_argument("--clear", action="store_true")
    p.set_defaults(func=cmd_harness)

    p = sub.add_parser("show", help="print the whole state")
    p.set_defaults(func=cmd_show)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
