#!/usr/bin/env python3
"""Watch the PR Review Bot's DM for the user's replies and get each one handled within about a minute.

The slack-pr-review loop checks Slack every 10 minutes, so a reply such as `post` could wait that long. This watcher uses no model: every POLL_SEC seconds it reads the bot DM with the bot token and looks for the user's replies that no check has handled yet (no bot reaction on the reply, and newer than its thread's `handled_ts` in the loop state). For such a reply:

- When no check is running, it starts one right away with `orca automations run`, like the dashboard's Check now, unless the schedule is paused or the next scheduled check starts within START_GRACE_SEC.
- When a check is running, it sends that check's Orca Run a `status` message with subject `slack-reply`, which wakes the check from its wait so it handles the reply at once. The message comes from the watcher's own Orca terminal, created once and stored in watch.json.
- A claim held by a check whose Orca terminal no longer exists is released first, so the new check is not refused.

Each reply gets at most MAX_ACTIONS starts or wakes, RETRY_SEC apart (or at once when the check it woke has ended), so a reply the loop cannot act on does not start checks forever.

`--pending` prints the unhandled replies as JSON lines (channel, ts, thread_ts, pr, text) and exits: the loop's INBOX. `--once` runs one poll. `--install` and `--uninstall` add or remove the launchd agent that keeps the watcher running across restarts and logs to watch.log in the state folder; `--status` prints what it last did. Runs on the macOS system Python (3.9).
"""

import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True  # importing notify and state must not leave __pycache__ in this git checkout
import notify  # noqa: E402  # pyright: ignore[reportMissingImports]
import state  # noqa: E402  # pyright: ignore[reportMissingImports]

AUTOMATION = "slack-pr-review"
POLL_SEC = 20
RETRY_SEC = 300
MAX_ACTIONS = 3
START_GRACE_SEC = 60
WINDOW_SEC = 86400  # replies older than a day are left to the loop's own reading
CLAIM_STALE_SEC = 1800
WATCH = os.path.join(state.HOME, "watch.json")
LOG = os.path.join(state.HOME, "watch.log")
LABEL = "slack-pr-review.watch"
PLIST = os.path.expanduser("~/Library/LaunchAgents/{}.plist".format(LABEL))
ORCA = shutil.which("orca") or "/Applications/Orca.app/Contents/Resources/bin/orca"


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def log(text):
    os.makedirs(state.HOME, exist_ok=True)
    with open(LOG, "a") as f:
        f.write("{} {}\n".format(datetime.now().strftime("%Y-%m-%d %H:%M:%S"), text))


def load_watch():
    try:
        with open(WATCH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_watch(data):
    os.makedirs(state.HOME, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=state.HOME, prefix=".watch.", suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
    os.replace(tmp, WATCH)


def orca(args, timeout=30):
    """Run the Orca CLI outside any agent terminal and return its JSON result, or raise with its error."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("ORCA_")}
    out = subprocess.run([ORCA] + args + ["--json"], capture_output=True, text=True, timeout=timeout, env=env)
    try:
        data = json.loads(out.stdout)
    except ValueError:
        raise RuntimeError((out.stderr or out.stdout).strip()[:200] or "orca exited {}".format(out.returncode))
    if not data.get("ok", True):
        raise RuntimeError(str((data.get("error") or {}).get("code") or data.get("error")))
    return data.get("result", data)


class Slack:
    """The bot DM, read with the PR Review Bot's token."""

    def __init__(self):
        self.token, self.me, bot = notify.resolve(None)
        if bot != "pr-review":
            raise RuntimeError("the PR Review Bot is not set up (notify.py --setup)")
        self.bot_user = self.call("auth.test").get("user_id")
        self.channel = self.call("conversations.open", users=self.me)["channel"]["id"]
        self.threads = {}  # root ts -> (latest_reply, replies)

    def call(self, method, **params):
        data = notify.call(self.token, method, params, form=True)
        if not data.get("ok"):
            raise RuntimeError("{} refused: {}".format(method, data.get("error")))
        return data

    def pages(self, method, **params):
        out, cursor = [], None
        for _ in range(5):
            data = self.call(method, **(dict(params, cursor=cursor) if cursor else params))
            out += data.get("messages", [])
            cursor = (data.get("response_metadata") or {}).get("next_cursor")
            if not cursor:
                break
        return out

    def recent(self):
        """[(root ts, [messages])] for every thread, or lone message, with activity in the last WINDOW_SEC."""
        since = time.time() - WINDOW_SEC
        out = []
        for top in self.pages("conversations.history", channel=self.channel, limit=200):
            latest = top.get("latest_reply")
            if latest and float(latest) >= since:
                known = self.threads.get(top["ts"])
                if not known or known[0] != latest:
                    replies = self.pages("conversations.replies", channel=self.channel, ts=top["ts"], oldest="{:.6f}".format(since), limit=200)
                    self.threads[top["ts"]] = (latest, [m for m in replies if m.get("ts") != top["ts"]])
                out.append((top["ts"], [top] + self.threads[top["ts"]][1]))
            elif float(top.get("ts", 0)) >= since:
                out.append((top["ts"], [top]))
        return out


def handled_marks(st):
    """{thread root ts: newest handled reply ts} from the loop state."""
    marks = {}

    def mark(root, value):
        if root and value:
            marks[root] = max(marks.get(root, 0.0), float(value))

    for r in (st.get("reviews") or {}).values():
        thread = r.get("thread") or {}
        ask = r.get("ask") or {}
        mark(thread.get("ts"), thread.get("handled_ts"))
        mark(ask.get("thread_ts") or thread.get("ts"), ask.get("handled_ts"))
    for msg in (st.get("messages") or {}).values():
        ask = msg.get("ask") or {}
        mark(ask.get("thread_ts") or ask.get("ts"), ask.get("handled_ts"))
    return marks


def pending(slack):
    """The user's replies in the bot DM that no check has handled yet, oldest first."""
    st = state.load()
    marks = handled_marks(st)
    prs = {}
    for pr, r in (st.get("reviews") or {}).items():
        root = (r.get("thread") or {}).get("ts")
        if root:
            prs[root] = pr
    since = time.time() - WINDOW_SEC
    out = []
    for root, messages in slack.recent():
        for m in messages:
            if m.get("user") != slack.me or m.get("bot_id") or m.get("subtype") or float(m["ts"]) < since:
                continue
            if any(slack.bot_user in (r.get("users") or []) for r in m.get("reactions") or []):
                continue
            if float(m["ts"]) <= marks.get(root, 0.0):
                continue
            out.append({"channel": slack.channel, "ts": m["ts"], "thread_ts": root, "pr": prs.get(root), "text": (m.get("text") or "")[:500]})
    return sorted(out, key=lambda p: float(p["ts"]))


def owner_alive(owner):
    """The claim owner's state: none, live, stale (heartbeat too old), or gone (its Orca terminal no longer exists)."""
    if not owner:
        return "none"
    try:
        beat = datetime.strptime(owner["heartbeat"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (KeyError, ValueError):
        return "stale"
    if (datetime.now(timezone.utc) - beat).total_seconds() > CLAIM_STALE_SEC:
        return "stale"
    terminal = owner.get("terminal") or ""
    if terminal.startswith("term_"):
        try:
            orca(["terminal", "show", "--terminal", terminal])
        except RuntimeError as exc:
            if "stale" in str(exc) or "not_found" in str(exc):
                return "gone"
    return "live"


def automation():
    listing = orca(["automations", "list"])
    items = listing.get("automations", listing) if isinstance(listing, dict) else listing
    found = next((a for a in items if a.get("name") == AUTOMATION), None)
    if not found:
        raise RuntimeError("Orca automation '{}' not found".format(AUTOMATION))
    shown = orca(["automations", "show", "--id", found["id"]])
    return (shown or {}).get("automation", shown) or found


def own_terminal(watch):
    """The watcher's Orca terminal, the sender of its wake messages; created when missing."""
    handle = watch.get("terminal")
    if handle:
        try:
            orca(["terminal", "show", "--terminal", handle])
            return handle
        except RuntimeError:
            pass
    st = state.load()
    clone = (st.get("repos") or {}).get("UpstageAI/solar-system") or os.path.expanduser("~")
    created = orca(["terminal", "create", "--title", "slack-pr-review reply watcher", "--worktree", "path:" + clone])
    handle = (created.get("terminal") or created).get("handle")
    watch["terminal"] = handle
    log("created the watcher's Orca terminal {}".format(handle))
    return handle


def act(watch, waiting):
    """Start a check, or wake the running one, for replies that need it; record what was done on each."""
    now = time.time()
    st = state.load()
    owner = st.get("owner")
    alive = owner_alive(owner)
    due = []
    for p in waiting:
        entry = watch["replies"][p["ts"]]
        actions = entry.get("actions", [])
        if len(actions) >= MAX_ACTIONS:
            continue
        last = actions[-1] if actions else None
        woken_ended = last and last["kind"] == "wake" and (alive != "live" or (owner or {}).get("terminal") != last.get("owner"))
        if not last or now - last["at"] >= RETRY_SEC or woken_ended:
            due.append(entry)
    if not due:
        return
    if alive == "gone":
        state_release(owner["terminal"])
        log("released the claim of ended check {}".format(owner["terminal"]))
        alive, owner = "none", None
    if alive == "live":
        run = st.get("run")
        if not run:
            return
        sender = own_terminal(watch)
        body = "The user replied in the bot DM: " + ", ".join("{} ({})".format(e["pr"] or "no PR thread", e["text"][:60]) for e in due)
        orca(["orchestration", "send", "--from", sender, "--to", "run:" + run, "--type", "status", "--subject", "slack-reply", "--body", body])
        holder = (owner or {}).get("terminal")
        record = {"kind": "wake", "at": now, "owner": holder}
        log("woke the running check {} for {} repl{}".format(holder, len(due), "y" if len(due) == 1 else "ies"))
    else:
        auto = automation()
        if not auto.get("enabled"):
            if not watch.get("paused_noted"):
                log("the schedule is paused; not starting a check")
                watch["paused_noted"] = True
            return
        watch["paused_noted"] = False
        nxt = auto.get("nextRunAt")
        if nxt and 0 <= int(nxt) / 1000 - now <= START_GRACE_SEC:
            return
        orca(["automations", "run", auto["id"]])
        record = {"kind": "start", "at": now}
        log("started a check for {} repl{}".format(len(due), "y" if len(due) == 1 else "ies"))
    for entry in due:
        entry.setdefault("actions", []).append(record)


def state_release(terminal):
    subprocess.run([sys.executable, os.path.join(HERE, "state.py"), "release", "--terminal", terminal], capture_output=True, text=True)


def poll(slack, watch):
    waiting = pending(slack)
    replies = watch.setdefault("replies", {})
    for p in waiting:
        replies.setdefault(p["ts"], {"pr": p["pr"], "text": p["text"][:200], "first_seen": time.time(), "actions": []})
    for ts in list(replies):
        if ts not in {p["ts"] for p in waiting}:
            replies.pop(ts)
    if waiting:
        act(watch, waiting)
    watch["last_poll"] = now_iso()
    watch["pending"] = len(waiting)
    watch["pid"] = os.getpid()
    watch.pop("error", None)


def run_forever():
    log("watcher started (pid {}), polling every {}s".format(os.getpid(), POLL_SEC))
    slack = None
    while True:
        watch = load_watch()
        try:
            slack = slack or Slack()
            poll(slack, watch)
            pause = POLL_SEC
        except urllib.error.HTTPError as exc:
            pause = int(exc.headers.get("Retry-After") or 60) if exc.code == 429 else 60
            watch["error"] = "Slack HTTP {}".format(exc.code)
            log("Slack HTTP {}; waiting {}s".format(exc.code, pause))
        except Exception as exc:
            # A failed setup leaves slack unset, so the next round tries again; other errors keep the connection.
            pause = 60
            if watch.get("error") != str(exc):
                log("error: {}".format(exc))
            watch["error"] = str(exc)
        save_watch(watch)
        time.sleep(pause)


def install():
    os.makedirs(os.path.dirname(PLIST), exist_ok=True)
    path_dirs = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", os.path.dirname(ORCA)]
    spec = {
        "Label": LABEL,
        "ProgramArguments": ["/usr/bin/python3", os.path.realpath(__file__)],
        "RunAtLoad": True,
        "KeepAlive": True,
        "ThrottleInterval": 30,
        "StandardOutPath": LOG,
        "StandardErrorPath": LOG,
        # No bytecode caches: the scripts live in a git checkout.
        "EnvironmentVariables": {"PATH": ":".join(path_dirs), "HOME": os.path.expanduser("~"), "PYTHONDONTWRITEBYTECODE": "1"},
    }
    with open(PLIST, "wb") as f:
        plistlib.dump(spec, f)
    domain = "gui/{}".format(os.getuid())
    subprocess.run(["launchctl", "bootout", domain + "/" + LABEL], capture_output=True)
    out = subprocess.run(["launchctl", "bootstrap", domain, PLIST], capture_output=True, text=True)
    if out.returncode != 0:
        print("install: launchctl bootstrap failed: " + (out.stderr or out.stdout).strip())
        return 1
    print("installed {} ({}); log: {}".format(LABEL, PLIST, LOG))
    return 0


def uninstall():
    subprocess.run(["launchctl", "bootout", "gui/{}/{}".format(os.getuid(), LABEL)], capture_output=True)
    if os.path.exists(PLIST):
        os.remove(PLIST)
    print("uninstalled " + LABEL)
    return 0


def main():
    parser = argparse.ArgumentParser(description="Watch the bot DM for the user's replies and start or wake a slack-pr-review check for each one.")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--pending", action="store_true", help="print the user's unhandled replies as JSON lines and exit (the loop's INBOX)")
    group.add_argument("--once", action="store_true", help="run one poll and exit")
    group.add_argument("--status", action="store_true", help="print what the watcher last did")
    group.add_argument("--install", action="store_true", help="install and start the launchd agent")
    group.add_argument("--uninstall", action="store_true", help="stop and remove the launchd agent")
    args = parser.parse_args()
    if args.install:
        return install()
    if args.uninstall:
        return uninstall()
    if args.status:
        print(json.dumps(load_watch(), ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    if args.pending:
        for p in pending(Slack()):
            print(json.dumps(p, ensure_ascii=False))
        return 0
    if args.once:
        watch = load_watch()
        poll(Slack(), watch)
        save_watch(watch)
        print(json.dumps({k: watch.get(k) for k in ("last_poll", "pending", "replies")}, ensure_ascii=False, indent=2))
        return 0
    run_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
