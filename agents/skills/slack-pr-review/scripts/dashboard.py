#!/usr/bin/env python3
"""Terminal dashboard for the slack-pr-review loop.

The screen is a status view first: the loop is meant to stay running, so no single key press acts on it. Up and down (or a click) select a row in Reviews, Waiting on you, or Recent checks, and Enter (or a double click) opens it: a check opens its summary here (left and right step to the previous or next check from there), and a review opens its thread in the bot DM. A waiting question opens on a single click (or Enter), because it exists to be answered. Threads open in the Slack desktop app at the exact message with its thread pane showing (a slack:// link), or in the browser where the app is not installed. Every action lives in the actions menu behind `a`: check now (one check right away while the 10-minute schedule keeps going), stop or restart the current check, pause or resume the schedule, and switch the coordinator; each one that interrupts or changes the loop asks to confirm. `q` quits. The bottom-bar labels, menu items, and Yes or Cancel are clickable too, and the wheel moves the selection or scrolls a summary.

It shows the loop's health (running on schedule, paused, or failing, with the reason), the current check, every review in progress, waiting on the user, or tracked, the questions the bot asked the user that still wait for a reply (with the replies each one takes), and the recent checks. Each check is sorted into did something (with a plain line of what it did, by PR, read from its messages in the bot DM and its transcript), nothing new, skipped (another check held the loop), or failed; the filter chips (or `f`) show one kind or all, Did something is the default, and All folds runs of quiet or skipped checks into one row. A check started outside the schedule says whether a reply of the user's or Check now started it. A check's summary shows what it said in the bot DM, read from Slack with the bot's token: its messages by PR thread, and before each reply the user's messages it answered, then the check's own final message from its Codex transcript. Stopping a check closes its terminal and releases the loop claim; review workers keep going and the next check resumes them.

Standard library only (curses), so it runs on the macOS system Python. `--once` prints a plain-text snapshot instead.
"""

import curses
import glob
import threading
import platform
import re
import json
import os
import subprocess
import sys
import time
import unicodedata
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
STATE_PY = os.path.join(HERE, "state.py")
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True  # importing notify and state must not leave __pycache__ in this git checkout
AUTOMATION_NAME = "slack-pr-review"
KST = timezone(timedelta(hours=9))
SESSION_GLOBS = [os.path.expanduser("~/Library/Application Support/orca/codex-accounts/*/home/sessions"), os.path.expanduser("~/.codex/sessions")]
REFRESH_SEC = 10
LIVE_REVIEW = ("queued", "running", "gate_flat", "fix_queued", "fix_running")
WAITING = ("awaiting_post",)
TRACKED = ("tracking",)
STATUS_LABEL = {
    "queued": "queued", "running": "reviewing", "gate_flat": "reviewing", "fix_queued": "fix check queued", "fix_running": "checking fixes",
    "awaiting_post": "waiting on you", "tracking": "watching for fixes", "approved": "approved", "done": "done", "closed": "closed",
    "failed": "failed", "skipped": "skipped",
}
STAGE_LABEL = {"review-a": "Codex", "review-b": "Claude", "review-c": "Kimi", "merge": "merge", "audit": "audit", "single": "review"}
DOUBLE_CLICK_SEC = 0.45
# The filter chips of Recent checks; "did" also shows running and failed checks, so the default view is everything worth reading.
FILTERS = [("did", "Did something"), ("quiet", "Nothing new"), ("skipped", "Skipped"), ("failed", "Failed"), ("all", "All")]
KIND_MARK = {"did": "●", "running": "…", "quiet": "○", "skipped": "–", "failed": "✗", "unknown": "?"}
# The bot DM templates (SKILL.md step 8), matched on a message's first line, as the words the check list uses.
PHRASES = [
    (re.compile(r"review started"), "started a review"),
    (re.compile(r"review ready"), "review ready for you"),
    (re.compile(r"fix check started"), "started a fix check"),
    (re.compile(r"^Fix check ready"), "fix check ready for you"),
    (re.compile(r"^Posted to GitHub"), "posted to GitHub"),
    (re.compile(r"tracking ended"), "stopped tracking"),
    (re.compile(r"failed:"), "reported a failure"),
    (re.compile(r"not reviewed"), "decided not to review"),
    (re.compile(r"asked again"), "noted a repeat request"),
    (re.compile(r"^Review request"), "asked you about a request"),
    (re.compile(r"no new commits or replies"), "noted nothing new on GitHub yet"),
]
# The Slack desktop app, which opens slack:// links straight at a message and its thread.
SLACK_APP = platform.system() == "Darwin" and any(os.path.isdir(p) for p in ("/Applications/Slack.app", os.path.expanduser("~/Applications/Slack.app")))
# A bot DM message that is one numbered comment item of a ready or fix-check DM.
ITEM = re.compile(r"^\*{1,2}(\d+)\. ")
ACK_MARK = {"done": "✓ done", "loading": "… working on it", "x": "✗ failed"}


def run(cmd, timeout=20):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except Exception as exc:
        return None, str(exc)
    if out.returncode != 0:
        return None, (out.stderr or out.stdout).strip()[:300]
    return out.stdout, None


def orca_json(args):
    out, err = run(["orca"] + args + ["--json"])
    if out is None:
        return None, err
    try:
        data = json.loads(out)
    except ValueError:
        return None, "unparseable orca output"
    if not data.get("ok", True):
        return None, str((data.get("error") or {}).get("message"))
    return data.get("result", data), None


def load_state():
    out, err = run([sys.executable, STATE_PY, "show"])
    if out is None:
        return {}, err
    return json.loads(out), None


def kst(value):
    if not value:
        return None
    if isinstance(value, (int, float)) or str(value).isdigit():
        return datetime.fromtimestamp(int(value) / 1000, KST)
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).astimezone(KST)
    except ValueError:
        return None


def clock(dt):
    if dt is None:
        return "-"
    if dt.date() != datetime.now(KST).date():
        return dt.strftime("%b %d %H:%M")
    return dt.strftime("%H:%M")


def span(sec):
    sec = int(abs(sec))
    if sec < 90:
        return "{}s".format(sec)
    if sec < 5400:
        return "{}m".format(sec // 60)
    if sec < 172800:
        return "{}h {:02d}m".format(sec // 3600, (sec % 3600) // 60)
    return "{}d".format(sec // 86400)


def ago(dt):
    if dt is None:
        return "-"
    sec = (datetime.now(KST) - dt).total_seconds()
    return ("in " + span(sec)) if sec < 0 else (span(sec) + " ago")


class Transcripts:
    """Final messages of the loop's Codex runs, matched to Orca runs by start time."""

    def __init__(self):
        self.cache = {}
        self.matched = {}

    def for_run(self, started):
        """(finished, summary, error) of the transcript that began within 90 s of the run's start, or None."""
        if started is None:
            return None
        known = self.matched.get(started)
        if known:
            return self.parse(known)
        best = None
        for root in SESSION_GLOBS:
            for base in glob.glob(root):
                for day in (0, 1):
                    folder = os.path.join(base, (started - timedelta(days=day)).strftime("%Y/%m/%d"))
                    for path in glob.glob(os.path.join(folder, "rollout-*.jsonl")):
                        stamp = os.path.basename(path)[8:27]
                        try:
                            t = datetime.strptime(stamp, "%Y-%m-%dT%H-%M-%S").replace(tzinfo=KST)
                        except ValueError:
                            continue
                        gap = (t - started).total_seconds()
                        if -5 <= gap <= 90 and (best is None or abs(gap) < best[0]):
                            best = (abs(gap), path)
        if not best:
            return None
        self.matched[started] = best[1]
        return self.parse(best[1])

    def parse(self, path):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            return None
        hit = self.cache.get(path)
        if hit and hit[0] == mtime:
            return hit[1]
        last, done, error, ended, refused, claim_call = None, False, None, None, False, None
        actions = {"posts": 0, "workers": 0, "messages": 0}
        with open(path, errors="replace") as f:
            for line in f:
                if '"custom_tool_call"' in line:
                    # Count invocations only (python3 .../notify.py ...), not commands that read the scripts; a notify call that only reacts is not a message.
                    actions["posts"] += len(re.findall(r"ghreview\.py\W{1,6}post\b", line))
                    actions["workers"] += len(re.findall(r"orchestration\W{1,6}worker-start", line)) + line.count("kimi -p")
                    calls = re.findall(r"python3 \S*notify\.py([^\"]{0,300})", line)
                    actions["messages"] += sum(1 for args in calls if not re.search(r"--(?:react|unreact|state|which|setup|help)", args))
                if claim_call and claim_call in line and '"custom_tool_call_output"' in line:
                    # The loop claim was refused (exit 3): another check holds the loop, so this one did nothing.
                    refused = refused or bool(re.search(r'exit_code\\*":3\b', line))
                    claim_call = None
                    continue
                if "state.py claim" in line and '"custom_tool_call"' in line:
                    try:
                        claim_call = json.loads(line).get("payload", {}).get("call_id")
                    except ValueError:
                        pass
                    continue
                if '"task_complete"' not in line and '"agent_message"' not in line:
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                payload = record.get("payload", {})
                if payload.get("type") == "task_complete":
                    done = True
                    ended = kst(record.get("timestamp")) or ended
                    last = payload.get("last_agent_message") or last
                    error = (payload.get("error") or {}).get("message") or error
                elif payload.get("type") == "agent_message":
                    last = payload.get("message") or last
        # (finished, final message, error, transcript path, finish time, whether the loop claim was refused, counts of posts, workers started, and DMs sent)
        result = (done, (last or "").strip(), error, path, ended or (datetime.fromtimestamp(mtime, KST) if done else None), refused, actions)
        self.cache[path] = (mtime, result)
        return result


def cols(text):
    """Terminal columns a string takes: wide characters (Korean, CJK) take two."""
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in text)


def fit(text, width):
    """Cut text to at most width terminal columns, marking a cut with an ellipsis."""
    if cols(text) <= width:
        return text
    out, used = "", 0
    for ch in text:
        w = 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
        if used + w > width - 1:
            break
        out += ch
        used += w
    return out + "…"


def cut(text, width):
    """The longest start of text that fits in width terminal columns (at least one character)."""
    used = 0
    for i, ch in enumerate(text):
        used += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
        if used > width:
            return text[: max(1, i)]
    return text


def wrap(text, width):
    """Lines of at most width terminal columns, broken at spaces where possible."""
    out = []
    for raw in (text or "").splitlines() or [""]:
        line, used = "", 0
        for word in re.split(r"(\s+)", raw):
            if not word:
                continue
            if used + cols(word) > width and line.strip():
                out.append(line.rstrip())
                line, used = "", 0
                if word.isspace():
                    continue
            while cols(word) > width:
                head = cut(word, width - used)
                out.append(line + head)
                line, used, word = "", 0, word[len(head):]
            line += word
            used += cols(word)
        out.append(line.rstrip())
    return out


def slack_plain(text):
    """A Slack message's stored text as plain text: links become their labels, bold marks and HTML escapes go away."""
    text = re.sub(r"<(https?://[^|>]+)\|([^>]+)>", r"\2", text or "")
    text = re.sub(r"<(https?://[^>]+)>", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", r"\1", text)
    text = text.replace("**", "")
    text = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", r"\1", text)
    return text.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")


def draw_box(win, height, width, title):
    """Plain Unicode border, so it renders the same in every terminal."""
    try:
        win.addstr(0, 0, "┌" + "─" * (width - 2) + "┐")
        for row in range(1, height - 1):
            win.addstr(row, 0, "│")
            win.addstr(row, width - 1, "│")
        win.addstr(height - 1, 0, "└" + "─" * (width - 2))
        win.insstr(height - 1, width - 1, "┘")
        win.addstr(0, 2, " {} ".format(title), curses.A_BOLD)
    except curses.error:
        pass


def headline(text, width):
    for line in (text or "").splitlines():
        line = line.strip().lstrip("#").strip().replace("**", "").replace("`", "")
        if line and not line.startswith("|") and not line.startswith("---"):
            return line[:width]
    return ""


def claim_exit(tr):
    """True when a check ended at once because another check held the loop claim: its claim call exited 3, or (for a transcript where that is not visible) its short final message says so."""
    if tr[5]:
        return True
    t = (tr[1] or "").lower()
    return len(t) < 800 and ("another" in t or "다른" in t) and any(k in t for k in ("claim", "owns the loop", "already", "holds", "실행권"))


def short_error(error):
    if not error:
        return ""
    if "usage limit" in error.lower():
        until = error.split("try again at", 1)[1].strip().rstrip(".") if "try again at" in error else ""
        return "out of usage" + (" until " + until if until else "")
    return error[:120]


def watcher_status():
    """(level, text) for the reply watcher from its watch.json: ok when it polled in the last two minutes."""
    path = os.path.join(os.environ.get("SLACK_PR_REVIEW_HOME") or os.path.expanduser("~/.local/state/slack-pr-review"), "watch.json")
    try:
        with open(path) as f:
            w = json.load(f)
    except (OSError, ValueError):
        return "off", "Reply watcher: not installed (watch.py --install)"
    last = kst(w.get("last_poll"))
    if last is None or (datetime.now(KST) - last).total_seconds() > 120:
        return "off", "Reply watcher: stopped, last looked {}".format(ago(last))
    if w.get("error"):
        return "error", "Reply watcher: " + str(w["error"])[:60]
    return "ok", "Reply watcher: on, looked {}".format(ago(last))


def describe(groups, labels):
    """One plain line of what a check did in the bot DM, by PR, such as "#1794: posted to GitHub, answered you"."""
    parts = []
    for root, events in groups:
        did, heard = [], False
        for e in events:
            if e["kind"] == "you":
                heard = True
                if e.get("ack") == "unanswered" and "your reply still waits" not in did:
                    did.append("your reply still waits")
                continue
            if e["kind"] == "items":
                continue
            first = (e["text"].strip().splitlines() or [""])[0]
            phrase = next((words for rx, words in PHRASES if rx.search(first)), "answered you" if heard else "sent a note")
            if phrase not in did:
                did.append(phrase)
        if did:
            parts.append("{}: {}".format(labels.get(root, "bot DM"), ", ".join(did)))
    return " · ".join(parts)


def check_key(run_record):
    """A check's identity that survives new checks being added to the list."""
    return run_record.get("id") or run_record.get("runNumber") or run_record.get("startedAt")


def plural(n, word):
    return "{} {}{}".format(n, word, "" if n == 1 else "s")


def payload_items(path):
    try:
        with open(path) as f:
            return [i for i in json.load(f).get("items") or [] if isinstance(i, dict)]
    except (OSError, ValueError, TypeError, AttributeError):
        return []


def waiting_asks(st, thread_target):
    """The questions the bot asked the user in its DM that still wait for a reply, oldest first: key, what is asked, how to reply, when, and the link that opens it."""
    out = []
    for key, msg in (st.get("messages") or {}).items():
        a = msg.get("ask") or {}
        if a.get("status") == "asked":
            prs = ", ".join("#" + p.split("#")[-1] for p in msg.get("prs") or []) or "A PR"
            target = {"channel": a.get("channel"), "message": a.get("ts"), "thread": a.get("thread_ts") or a.get("ts"), "web": a.get("permalink"), "label": prs + " question"}
            out.append({"key": "message/" + key, "at": kst(a.get("asked_at")), "target": target, "reply": "`review` or `skip`", "what": "{}: unclear review request from {}. Review it?".format(prs, msg.get("from_name") or "someone")})
    for pr, r in (st.get("reviews") or {}).items():
        a = r.get("ask") or {}
        if a.get("status") != "asked":
            continue
        n = "#" + pr.split("#")[-1]
        items = payload_items(a.get("payload"))
        approve = bool(items) and all(i.get("type") == "approve" for i in items)
        if a.get("kind") == "post_first":
            what = "{} review ready: {}".format(n, "approve it with LGTM?" if approve else "post its {}?".format(plural(len(items), "comment")) if items else "post it?")
            reply = "`post`, `post 1 3`, `edit <n>: …`, `posted`, or `skip`"
        elif a.get("kind") == "post_fix":
            replies = sum(1 for i in items if i.get("type") == "reply")
            parts = ["1 reply" if replies == 1 else "{} replies".format(replies)] if replies else []
            parts += [plural(len(items) - replies, "new comment")] if len(items) > replies else []
            what = "{} fix check: {}".format(n, "approve it with LGTM?" if approve else "post {}?".format(" and ".join(parts)) if parts else "post it?")
            reply = "`post`, `post 1 3`, `edit <n>: …`, `skip`, or `stop`"
        else:
            what, reply = "{}: a reply is needed".format(n), "in its thread"
        target = thread_target(pr, r)
        if a.get("ts"):
            target = dict(target, channel=a.get("channel") or target["channel"], message=a["ts"], thread=a.get("thread_ts") or target["thread"], web=a.get("permalink") or target["web"])
        out.append({"key": "review/" + pr, "at": kst(a.get("asked_at")), "target": target, "what": what, "reply": reply})
    out.sort(key=lambda a: a["at"] or datetime.now(KST))
    return out


class SlackLog:
    """The bot DM as the PR Review Bot sees it, so a check's summary can show what the check said there and which of the user's replies it answered.

    It is read in the background, only while a summary is open, at most once a minute; a thread is read again only when it has new replies.
    """

    TTL = 60

    def __init__(self):
        self.fetched = 0
        self.busy = False
        self.error = None
        self.top = []
        self.threads = {}
        self.bot_user = None
        self.version = 0  # bumped each time a read finishes, so results computed from the old data are recomputed

    def refresh(self, channel, since):
        if not channel or self.busy or time.time() - self.fetched < self.TTL:
            return
        self.busy = True
        self.fetched = time.time()
        threading.Thread(target=self._fetch, args=(channel, since), daemon=True).start()

    def _fetch(self, channel, since):
        try:
            import notify  # the bot token and the Slack API call  # pyright: ignore[reportMissingImports]
            token, _, bot = notify.resolve(None)
            if bot != "pr-review":
                raise RuntimeError("the PR Review Bot is not set up")
            if not self.bot_user:
                self.bot_user = notify.call(token, "auth.test", {}, form=True).get("user_id")

            def pages(method, params):
                out, cursor = [], None
                for _ in range(10):
                    data = notify.call(token, method, dict(params, cursor=cursor) if cursor else params, form=True)
                    if not data.get("ok"):
                        raise RuntimeError("{} refused: {}".format(method, data.get("error")))
                    out += data.get("messages", [])
                    cursor = (data.get("response_metadata") or {}).get("next_cursor")
                    if not cursor:
                        break
                return out

            top = pages("conversations.history", {"channel": channel, "limit": 200})
            threads = dict(self.threads)
            for m in top:
                latest = m.get("latest_reply")
                if not latest or float(latest) < since or (threads.get(m["ts"]) or (None,))[0] == latest:
                    continue
                threads[m["ts"]] = (latest, pages("conversations.replies", {"channel": channel, "ts": m["ts"], "limit": 200})[1:])
            self.top, self.threads, self.error = top, threads, None
            self.version += 1
        except Exception as exc:
            self.error = "Could not read the bot DM: {}".format(exc)
        finally:
            self.busy = False

    def is_bot(self, m):
        return bool(m.get("bot_id")) or (self.bot_user and m.get("user") == self.bot_user)

    def events(self, start, end):
        """[(thread root ts, [event])] for start to end (unix seconds): the bot's messages in that window, and before each of its replies the user's messages it answered.

        Each event is a dict: kind (bot, items, or you), ts, text, and for kind you the bot's reaction on it (ack: done, loading, x, or unanswered). Consecutive comment items fold into one items event listing their numbers.
        """
        groups = []
        for root in self.top:
            thread = [root] + (self.threads.get(root["ts"]) or (None, []))[1]
            out, waiting = [], []
            for m in thread:
                if not self.is_bot(m):
                    waiting.append(m)
                    continue
                if start <= float(m.get("ts", 0)) <= end:
                    out += [{"kind": "you", "ts": u["ts"], "text": slack_plain(u.get("text")), "ack": self.ack(u)} for u in waiting]
                    item = ITEM.match(m.get("text") or "")
                    if item and out and out[-1]["kind"] == "items":
                        out[-1]["numbers"].append(item.group(1))
                    elif item:
                        out.append({"kind": "items", "ts": m["ts"], "numbers": [item.group(1)]})
                    else:
                        out.append({"kind": "bot", "ts": m["ts"], "text": slack_plain(m.get("text"))})
                waiting = []
            out += [{"kind": "you", "ts": u["ts"], "text": slack_plain(u.get("text")), "ack": self.ack(u) or "unanswered"} for u in waiting if start <= float(u.get("ts", 0)) <= end]
            for e in out:
                if e["kind"] == "items":
                    n = e["numbers"]
                    e["text"] = "Comment item{} {} in the thread: the exact text that would be posted".format("s" if len(n) > 1 else "", n[0] if len(n) == 1 else "{} to {}".format(n[0], n[-1]))
            if out:
                groups.append((root["ts"], out))
        groups.sort(key=lambda g: float(g[1][0]["ts"]))
        return groups

    def ack(self, m):
        for r in m.get("reactions") or []:
            if r.get("name") in ACK_MARK and self.bot_user in (r.get("users") or []):
                return r["name"]
        return None


class Model:
    """Everything the screen shows, loaded in one pass."""

    def __init__(self, transcripts):
        self.transcripts = transcripts
        self.errors = []
        self.auto = None
        self.runs = []
        self.state = {}
        self.kimi_effort = "?"

    def load(self):
        self.errors = []
        listing, err = orca_json(["automations", "list"])
        self.auto = None
        if listing is None:
            self.errors.append("Orca: " + str(err))
        else:
            items = listing.get("automations", listing) if isinstance(listing, dict) else listing
            found = next((a for a in items if a.get("name") == AUTOMATION_NAME), None)
            if found:
                shown, _ = orca_json(["automations", "show", "--id", found["id"]])
                self.auto = (shown or {}).get("automation", shown) or found
                runs, _ = orca_json(["automations", "runs", "--id", found["id"]])
                self.runs = (runs or {}).get("runs", [])[:100]
            else:
                self.errors.append("Orca automation '{}' not found".format(AUTOMATION_NAME))
        self.state, err = load_state()
        if err:
            self.errors.append("state: " + err)
        self.kimi_effort = "?"
        try:
            in_thinking = False
            with open(os.path.expanduser("~/.kimi-code/config.toml")) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("["):
                        in_thinking = line == "[thinking]"
                    elif in_thinking and line.startswith("effort"):
                        self.kimi_effort = line.split("=", 1)[1].strip().strip('"')
        except OSError:
            pass

    def live(self):
        owner = (self.state or {}).get("owner")
        if not owner:
            return None
        beat = kst(owner.get("heartbeat"))
        if beat is None or (datetime.now(KST) - beat).total_seconds() > 1800:
            return None
        return owner, beat

    def checks(self):
        out = []
        for r in self.runs:
            started = kst(r.get("startedAt") or r.get("scheduledFor"))
            out.append((r, started, self.transcripts.for_run(started)))
        return out

    def health(self):
        """(level, text): ok, paused, or failing, from the schedule and the latest finished checks."""
        if not self.auto:
            return "failing", "the scheduled loop is missing"
        if not self.auto.get("enabled"):
            return "paused", "the 10-minute checks are paused"
        seen = [t for _, _, t in self.checks() if t]
        if not seen:
            return "ok", "checking Slack every 10 minutes"
        newest = seen[0]
        if newest[2]:
            failed = 0
            for t in seen:
                if not t[2]:
                    break
                failed += 1
            return "failing", "the last {} check{} failed: {}".format(failed, "" if failed == 1 else "s", short_error(newest[2]))
        return "ok", "a check is running now" if not newest[0] else "checking Slack every 10 minutes"


class Dashboard:
    def __init__(self, screen):
        self.screen = screen
        self.model = Model(Transcripts())
        self.slack = SlackLog()
        self.mode = "main"
        self.menu_index = 0
        self.scroll = 0
        self.sel = 0          # index of the check whose summary is open
        self.detail_key = None
        self.offset = 0
        self.items = []       # selectable rows of the main view, in screen order: (kind, key, value)
        self.cur = None       # (kind, key) of the selected row
        self.last_click = (None, 0)
        self.loaded_at = 0
        self.team = None
        self.filter = "did"
        self.visible = []     # indices of the checks the current filter shows, newest first
        self.kind_cache = {}
        self.toast = ""
        self.toast_until = 0
        self.zones = []
        curses.curs_set(0)
        # Mouse reporting is switched on here and decoded below, not through curses' own mouse support:
        # the macOS curses library misreads the newer (SGR) reports some terminals send, so clicks were lost.
        sys.stdout.write(MOUSE_ON)
        sys.stdout.flush()
        curses.use_default_colors()
        palette = [curses.COLOR_GREEN, curses.COLOR_YELLOW, curses.COLOR_RED, curses.COLOR_CYAN, curses.COLOR_MAGENTA, curses.COLOR_BLUE]
        for i, color in enumerate(palette, start=1):
            curses.init_pair(i, color, -1)
        curses.init_pair(7, curses.COLOR_BLACK, curses.COLOR_GREEN)
        curses.init_pair(8, curses.COLOR_BLACK, curses.COLOR_YELLOW)
        curses.init_pair(9, curses.COLOR_WHITE, curses.COLOR_RED)
        self.c = {name: curses.color_pair(i) for i, name in enumerate(["green", "yellow", "red", "cyan", "magenta", "blue"], start=1)}
        self.badge = {"ok": curses.color_pair(7) | curses.A_BOLD, "paused": curses.color_pair(8) | curses.A_BOLD, "failing": curses.color_pair(9) | curses.A_BOLD}
        self.screen.timeout(REFRESH_SEC * 1000)

    # text helpers
    def put(self, y, x, text, attr=0):
        h, w = self.screen.getmaxyx()
        if y < 0 or y >= h or x >= w:
            return
        try:
            self.screen.addnstr(y, x, text, max(0, w - x - 1), attr)
        except curses.error:
            pass

    def rule(self, y, title):
        h, w = self.screen.getmaxyx()
        self.put(y, 0, "─" * (w - 1), curses.A_DIM)
        self.put(y, 2, " {} ".format(title), curses.A_BOLD)
        return y + 1

    def zone(self, y, x0, x1, action, value=None):
        """Remember a clickable area drawn this frame."""
        self.zones.append((y, x0, x1, action, value))

    def hit(self, y, x):
        for zy, x0, x1, action, value in reversed(self.zones):
            if zy == y and x0 <= x < x1:
                return action, value
        return None, None

    def row(self, y, key):
        """Make screen row y selectable as key; when it is the selected row, draw the selection bar and return the attribute its text takes."""
        h, w = self.screen.getmaxyx()
        self.zone(y, 0, w, "select", key)
        if key != self.cur:
            return 0
        self.put(y, 0, " " * (w - 1), curses.A_REVERSE)
        self.put(y, 0, "▶", curses.A_REVERSE | curses.A_BOLD)
        return curses.A_REVERSE

    def dm_threads(self):
        """({thread root ts: "#N title"}, {thread root ts: "#N"}, the bot DM channel) from the state's PR and question threads."""
        st = self.model.state or {}
        full, short, channel = {}, {}, None
        for pr, r in (st.get("reviews") or {}).items():
            t = r.get("thread") or {}
            if t.get("ts"):
                full[t["ts"]] = "#{} {}".format(pr.split("#")[-1], (r.get("title") or "").split("] ", 1)[-1])
                short[t["ts"]] = "#" + pr.split("#")[-1]
                channel = channel or t.get("channel")
        for msg in (st.get("messages") or {}).values():
            a = msg.get("ask") or {}
            root = a.get("thread_ts") or a.get("ts")
            if root and root not in full:
                prs = ", ".join("#" + p.split("#")[-1] for p in msg.get("prs") or []) or "a review request"
                full[root], short[root] = "Question about " + prs, "question about " + prs
        return full, short, channel

    def refresh_slack(self):
        _, _, channel = self.dm_threads()
        checks = self.model.checks()
        oldest = min((c[1] for c in checks if c[1]), default=datetime.now(KST))
        self.slack.refresh(channel, oldest.timestamp() - 3600)

    def classify(self, started, tr):
        """(kind, text) for one check: did (and what it did, from the bot DM and its transcript), running, quiet, skipped, failed, or unknown."""
        if tr is None:
            return "unknown", "no Codex transcript found for this check"
        if tr[2]:
            return "failed", "failed: " + short_error(tr[2])
        if tr[0] and claim_exit(tr):
            return "skipped", "skipped: another check was still running"
        key = (tr[3], tr[4], self.slack.version)
        if tr[0] and key in self.kind_cache:
            return self.kind_cache[key]
        end = (tr[4].timestamp() if tr[4] else time.time()) if tr[0] else time.time()
        text = describe(self.slack.events(started.timestamp() - 5, end + 5), self.dm_threads()[1]) if started and self.slack.top else ""
        acts = tr[6]
        extra = ["started {}".format(plural(acts["workers"], "review agent"))] if acts["workers"] else []
        if not text and acts["posts"]:
            extra.append("posted to GitHub")
        if not text and acts["messages"]:
            extra.append("sent {}".format(plural(acts["messages"], "DM message")))
        text = "; ".join(t for t in (text, ", ".join(extra)) if t)
        if not tr[0]:
            return "running", "running now" + (": " + text if text else "")
        result = ("did", text) if text else ("quiet", "nothing new to act on")
        self.kind_cache[key] = result
        return result

    def trigger(self, run_record, started):
        """How a check started: on schedule, after the user's reply (the reply watcher started it), or from Check now."""
        if run_record.get("trigger") == "scheduled" or started is None:
            return ""
        path = os.path.join(os.environ.get("SLACK_PR_REVIEW_HOME") or os.path.expanduser("~/.local/state/slack-pr-review"), "watch.json")
        try:
            with open(path) as f:
                starts = json.load(f).get("started") or []
        except (OSError, ValueError):
            starts = []
        t = started.timestamp()
        return "started by your reply" if any(-5 <= t - float(x) <= 120 for x in starts) else "started by Check now"

    def check_rows(self, checks):
        """The Recent checks rows the current filter shows, newest first. All folds runs of quiet or skipped checks into one row."""
        kinds = [self.classify(started, tr) for _, started, tr in checks]
        self.counts = {"did": 0, "quiet": 0, "skipped": 0, "failed": 0, "all": len(checks)}
        for kind, _ in kinds:
            self.counts[{"running": "did", "unknown": "failed"}.get(kind, kind)] += 1
        rows = []
        for i, ((r, started, tr), (kind, text)) in enumerate(zip(checks, kinds)):
            group = {"running": "did", "unknown": "failed"}.get(kind, kind)
            if self.filter != "all" and group != self.filter:
                continue
            last = rows[-1] if rows else None
            if self.filter == "all" and kind in ("quiet", "skipped") and last and last["kind"] == kind and last["indices"][-1] == i - 1:
                last["indices"].append(i)
                last["oldest"] = started
                continue
            rows.append({"key": ("check", check_key(r)), "kind": kind, "indices": [i], "started": started, "oldest": started, "text": text, "trigger": self.trigger(r, started)})
        for row in rows:
            n = len(row["indices"])
            if n > 1:
                row["text"] = "{} checks since {}: {}".format(n, clock(row["oldest"]), "nothing new to act on" if row["kind"] == "quiet" else "all skipped, another check was still running")
        self.visible = [i for row in rows for i in row["indices"]]
        return rows

    def move(self, step):
        keys = [(kind, key) for kind, key, _ in self.items]
        if keys:
            i = keys.index(self.cur) if self.cur in keys else 0
            self.cur = keys[max(0, min(len(keys) - 1, i + step))]

    def open_selected(self):
        """Open the selected row: a check's summary here, or a review's or question's thread in Slack."""
        item = next((it for it in self.items if (it[0], it[1]) == self.cur), None)
        if not item:
            return
        kind, _, value = item
        if kind == "check":
            checks = self.model.checks()
            self.sel, self.mode, self.scroll = value, "details", 0
            self.detail_key = check_key(checks[value][0]) if value < len(checks) else None
        else:
            self.open_slack(value)

    def back_to_main(self):
        """Leave a summary with its check's row selected (the folded row that holds it, in All), so Enter opens it again."""
        checks = self.model.checks()
        if checks:
            index = self.detail_index(checks)
            row = next((row for row in self.check_rows(checks) if index in row["indices"]), None)
            self.cur = row["key"] if row else ("check", check_key(checks[index][0]))
        self.mode = "main"

    def detail_index(self, checks):
        """Index of the check whose summary is open, found by its key, so a new check arriving does not change it."""
        index = next((i for i, (r, _, _) in enumerate(checks) if check_key(r) == self.detail_key), None)
        self.sel = index if index is not None else max(0, min(self.sel, len(checks) - 1))
        return self.sel

    def step(self, direction):
        """Open the newer (-1) or older (+1) check among those the current filter shows."""
        checks = self.model.checks()
        if not checks:
            return
        index = self.detail_index(checks)
        shown = [i for row in self.check_rows(checks) for i in row["indices"]] or list(range(len(checks)))
        if index in shown:
            j = shown.index(index) + direction
            index = shown[j] if 0 <= j < len(shown) else index
        else:
            index = max(0, min(len(checks) - 1, index + direction))
        self.sel, self.detail_key, self.scroll = index, check_key(checks[index][0]), 0

    def footer(self, parts):
        """Draw the bottom bar from (label, action) pairs and make each labeled part clickable."""
        h, w = self.screen.getmaxyx()
        self.put(h - 1, 0, " " * (w - 1), curses.A_REVERSE)
        x = 1
        for label, action in parts:
            self.put(h - 1, x, label, curses.A_REVERSE | (curses.A_BOLD if action else 0))
            if action:
                self.zone(h - 1, x, x + cols(label), action)
            x += cols(label) + 4
        self.put(h - 1, w - 26, "refreshes every {}s".format(REFRESH_SEC), curses.A_REVERSE | curses.A_DIM)

    def open_link(self, url, done=None):
        if not url:
            self.say("No link to open for that row.")
            return
        opener = "open" if platform.system() == "Darwin" else "xdg-open"
        try:
            subprocess.Popen([opener, url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.say(done or "Opened " + url)
        except OSError as exc:
            self.say("Could not open the link: {}".format(exc))

    def team_id(self):
        """The Slack workspace id, from the bot token (asked once), or None when it cannot be read."""
        if self.team is None:
            self.team = ""
            try:
                import notify  # pyright: ignore[reportMissingImports]
                token, _, bot = notify.resolve(None)
                if bot == "pr-review":
                    self.team = notify.call(token, "auth.test", {}, form=True).get("team_id") or ""
            except Exception:
                pass
        return self.team or None

    def open_slack(self, target):
        """Open a bot DM message with its thread in the Slack app, ready for a reply, or its web link when the app or the workspace id is missing."""
        team = self.team_id() if SLACK_APP else None
        if team and target.get("channel") and target.get("message"):
            url = "slack://channel?team={}&id={}&message={}".format(team, target["channel"], target["message"])
            if target.get("thread"):
                url += "&thread_ts=" + target["thread"]
            self.open_link(url, "Opened the {} thread in Slack. Reply there.".format(target.get("label") or "bot DM"))
        else:
            self.open_link(target.get("web"), "Opened the {} thread in the browser. Reply there.".format(target.get("label") or "bot DM"))

    def thread_target(self, pr, review):
        """Where a PR's bot DM thread is: the root message, its thread, and a web link for when the Slack app is not available."""
        thread = review.get("thread") or {}
        return {"channel": thread.get("channel"), "message": thread.get("ts"), "thread": thread.get("ts"), "web": self.thread_link(review), "label": "#" + pr.split("#")[-1]}

    def thread_link(self, review):
        """The PR's bot DM thread (its root message), or the PR on GitHub when no thread link can be built."""
        ask = review.get("ask") or {}
        stored = review.get("dm_permalink") or ask.get("permalink") or ""
        thread = review.get("thread") or {}
        host = re.match(r"(https://[^/]+)/archives/", stored)
        if host and thread.get("channel") and thread.get("ts"):
            return "{}/archives/{}/p{}".format(host.group(1), thread["channel"], thread["ts"].replace(".", ""))
        return stored or review.get("url")

    def say(self, text):
        self.toast = text
        self.toast_until = time.time() + 12

    # main view
    def draw_main(self):
        s = self.screen
        s.erase()
        self.zones = []
        h, w = s.getmaxyx()
        m = self.model
        now = datetime.now(KST)
        level, text = m.health()
        label = {"ok": " RUNNING ", "paused": " PAUSED ", "failing": " FAILING "}[level]
        self.put(0, 0, " PR Review Loop ", curses.A_BOLD | curses.A_REVERSE)
        self.put(0, 18, label, self.badge[level])
        self.put(0, 19 + len(label), text, {"ok": 0, "paused": self.c["yellow"], "failing": self.c["red"]}[level])
        self.put(0, w - 13, now.strftime("%H:%M:%S KST"), curses.A_DIM)

        y = 2
        auto = m.auto or {}
        nxt = kst(auto.get("nextRunAt"))
        live = m.live()
        checks = m.checks()
        last = next(((r, t, tr) for r, t, tr in checks if tr and tr[0]), None)
        col = max(28, (w - 2) // 4)
        cards = [
            ("Next check", "{} ({})".format(clock(nxt), ago(nxt)) if auto.get("enabled") and nxt else "paused", 0 if auto.get("enabled") else self.c["yellow"]),
            ("Current check", "running, heartbeat {}".format(ago(live[1])) if live else "none running", self.c["green"] if live else curses.A_DIM),
            ("Last check", "{} {}".format(clock(last[1]), "failed" if last[2][2] else "skipped, another was running" if claim_exit(last[2]) else "ok") if last else "-", (self.c["red"] if last[2][2] else curses.A_DIM if claim_exit(last[2]) else self.c["green"]) if last else 0),
            ("Coordinator", "{}{}".format(auto.get("agentId") or "?", ", out of usage" if level == "failing" and "usage" in text else ""), self.c["red"] if level == "failing" and "usage" in text else 0),
        ]
        for i, (title, value, attr) in enumerate(cards):
            x = 1 + i * col
            self.put(y, x, title, curses.A_DIM)
            self.put(y + 1, x, value[: col - 2], attr | curses.A_BOLD)
        y += 3
        self.put(y, 1, "Reviewers: Codex, Claude Code, Kimi (effort {}) for big PRs; one reviewer for small PRs".format(m.kimi_effort), curses.A_DIM)
        wlevel, wtext = watcher_status()
        self.put(y, max(1, w - cols(wtext) - 2), wtext, {"ok": self.c["green"], "off": self.c["red"], "error": self.c["yellow"]}[wlevel])
        y += 2

        st = m.state or {}
        reviews = st.get("reviews") or {}
        rows = []
        for pr, r in reviews.items():
            status = r.get("status", "")
            updated = kst(r.get("updated_at"))
            if status in LIVE_REVIEW + WAITING + TRACKED or (updated and (now - updated).days < 2):
                rows.append((pr, r, status, updated))
        rank = {v: i for i, v in enumerate(LIVE_REVIEW + WAITING + TRACKED)}
        rows.sort(key=lambda x: (rank.get(x[2], 99), -(x[3].timestamp() if x[3] else 0)))
        asks = waiting_asks(st, self.thread_target)
        self.items = [("review", pr, self.thread_target(pr, r)) for pr, r, _, _ in rows]
        self.items += [("ask", a["key"], a["target"]) for a in asks]
        self.refresh_slack()
        check_rows = self.check_rows(checks)
        self.items += [("check", row["key"][1], row["indices"][0]) for row in check_rows]
        keys = [(k, key) for k, key, _ in self.items]
        if self.cur not in keys:
            self.cur = next((x for x in keys if x[0] == "check"), keys[0] if keys else None)

        y = self.rule(y, "Reviews")
        budget = max(3, h - y - 15)
        for pr, r, status, updated in rows[:budget]:
            sel = self.row(y, ("review", pr))
            attr = self.c["green"] if status in LIVE_REVIEW else self.c["yellow"] if status in WAITING else self.c["blue"] if status in TRACKED else curses.A_DIM
            dot = "●" if status in LIVE_REVIEW + WAITING + TRACKED else "○"
            label = "merged" if r.get("pr_state") == "MERGED" and status not in LIVE_REVIEW else STATUS_LABEL.get(status, status)
            self.put(y, 1, dot, attr | sel)
            self.put(y, 3, "#{:<6}".format(pr.split("#")[-1]), curses.A_BOLD | sel)
            self.put(y, 11, "{:<19}".format(label), attr | sel)
            detail = ""
            if status in ("fix_queued", "fix_running"):
                fixes = r.get("fixes") or [{}]
                detail = "fix check {} {}".format(fixes[-1].get("n", ""), "…" if status == "fix_running" else "queued")
            elif status in LIVE_REVIEW:
                chips = []
                for stage, wk in (r.get("workers") or {}).items():
                    if stage.startswith("fix-"):
                        continue
                    mark = {"running": "…", "succeeded": "✓", "done": "✓", "failed": "✗", "skipped": "–"}.get(wk.get("state"), "?")
                    chips.append("{} {}".format(STAGE_LABEL.get(stage, stage), mark))
                detail = "  ".join(chips)
            else:
                detail = "updated " + ago(updated)
            title = (r.get("title") or "").split("] ", 1)[-1]
            self.put(y, 31, fit(title, max(10, w - 31 - cols(detail) - 4)), sel)
            self.put(y, max(31, w - len(detail) - 2), detail, (curses.A_DIM if status not in LIVE_REVIEW else attr) | sel)
            y += 1
        if not rows:
            self.put(y, 3, "nothing in progress", curses.A_DIM)
            y += 1
        if len(rows) > budget:
            self.put(y, 3, "+{} more".format(len(rows) - budget), curses.A_DIM)
            y += 1
        y += 1

        y = self.rule(y, "Waiting on you" + ("  ({})".format(len(asks)) if asks else ""))
        self.put(y, 3, "Questions the PR Review bot asked you in Slack. Click one (or press Enter) to jump to its thread in Slack and reply there.", curses.A_DIM)
        y += 1
        for a in asks[:4]:
            sel = self.row(y, ("ask", a["key"]))
            self.put(y, 1, "●", self.c["yellow"] | sel)
            self.put(y, 3, fit(a["what"], w - 30), curses.A_BOLD | sel)
            self.put(y, 4 + cols(fit(a["what"], w - 30)), fit("reply " + a["reply"], max(0, w - 22 - cols(a["what"]))), curses.A_DIM | sel)
            self.put(y, w - 14, ago(a["at"]), curses.A_DIM | sel)
            y += 1
        if not asks:
            self.put(y, 3, "nothing right now", curses.A_DIM)
            y += 1
        y += 1

        y = self.rule(y, "Recent checks")
        x = 19
        for name, label in FILTERS:
            chip = " {} {} ".format(label, self.counts.get(name, 0))
            self.put(y - 1, x, chip, (curses.A_REVERSE | curses.A_BOLD) if name == self.filter else curses.A_DIM)
            self.zone(y - 1, x, x + cols(chip), "filter", name)
            x += cols(chip) + 1
        self.put(y - 1, x + 1, "f switch", curses.A_DIM)
        self.put(y, 3, "A check is one pass of the loop (every 10 minutes, and right after you reply): it reads Slack, acts on your replies, and starts or finishes reviews.", curses.A_DIM)
        y += 1
        rows = max(3, h - y - 3)
        pos = next((j for j, row in enumerate(check_rows) if row["key"] == self.cur), None)
        if pos is not None:
            if pos < self.offset:
                self.offset = pos
            elif pos >= self.offset + rows:
                self.offset = pos - rows + 1
        self.offset = max(0, min(self.offset, max(0, len(check_rows) - rows)))
        if not check_rows:
            self.put(y, 3, "no checks in this view; press f or click another filter", curses.A_DIM)
        shown_rows = check_rows[self.offset: self.offset + rows]
        text_x = 3 + max([cols(clock(row["started"])) for row in shown_rows] or [5]) + 2
        for row in shown_rows:
            sel = self.row(y, row["key"])
            kind = row["kind"]
            attr = {"did": 0, "running": self.c["green"], "failed": self.c["red"], "unknown": curses.A_DIM}.get(kind, curses.A_DIM)
            mark_attr = {"did": self.c["green"], "running": self.c["green"], "failed": self.c["red"]}.get(kind, curses.A_DIM)
            tag = row["trigger"]
            self.put(y, 1, KIND_MARK[kind], (mark_attr if not sel else 0) | sel | curses.A_BOLD * bool(sel))
            self.put(y, 3, clock(row["started"]), (curses.A_DIM if not sel else 0) | sel)
            room = w - text_x - 2 - (cols(tag) + 3 if tag else 0)
            self.put(y, text_x, fit(row["text"], room), (attr if not sel else 0) | sel)
            if tag:
                self.put(y, w - cols(tag) - 2, tag, curses.A_DIM | sel)
            y += 1

        if m.errors:
            self.put(h - 2, 1, m.errors[0], self.c["red"])
        elif self.toast and time.time() < self.toast_until:
            self.put(h - 2, 1, self.toast, self.c["cyan"])
        kind = (self.cur or ("",))[0]
        self.footer([("↑↓ or click select", None), ("Enter open " + ("its summary" if kind == "check" else "its Slack thread"), "open"), ("f filter checks", "cycle_filter"), ("a actions", "menu"), ("q quit", "quit")])
        s.refresh()

    # actions menu
    def actions(self):
        auto = self.model.auto or {}
        live = self.model.live()
        coordinator = auto.get("agentId") or "codex"
        other = "claude" if coordinator == "codex" else "codex"
        items = [("check", "Check now", "Runs one check immediately. The 10-minute schedule keeps going.", True)]
        items.append(("stop", "Stop the current check", "Closes the running check. Review workers keep going; the next check resumes them.", bool(live)))
        items.append(("restart", "Restart the current check", "Stops the running check and starts a fresh one right away.", bool(live)))
        if auto.get("enabled"):
            items.append(("pause", "Pause the 10-minute checks", "No new checks start until you resume. Not needed for a one-off check.", True))
        else:
            items.append(("resume", "Resume the 10-minute checks", "Checks start again every 10 minutes.", True))
        items.append(("switch", "Switch coordinator to {}".format({"claude": "Claude Code", "codex": "Codex"}[other]), "Use when {} is out of usage; switch back when it resets.".format({"claude": "Claude Code", "codex": "Codex"}[coordinator]), True))
        return items

    def draw_menu(self):
        self.draw_main()
        h, w = self.screen.getmaxyx()
        items = self.actions()
        width = min(w - 4, 78)
        height = len(items) * 2 + 4
        top, left = max(1, (h - height) // 2), max(1, (w - width) // 2)
        win = curses.newwin(height, width, top, left)
        win.erase()
        draw_box(win, height, width, "Actions")
        self.zones = [(row, 0, w, "menu_close", None) for row in range(h)]
        for i in range(len(items)):
            for dy in (0, 1):
                self.zone(top + 2 + i * 2 + dy, left, left + width, "menu_item", i)
        try:
            for i, (_, label, hint, enabled) in enumerate(items):
                row = 2 + i * 2
                selected = i == self.menu_index
                attr = (curses.A_REVERSE if selected else 0) | (0 if enabled else curses.A_DIM)
                win.addnstr(row, 2, (" {}. {} ".format(i + 1, label)).ljust(width - 4), width - 4, attr | curses.A_BOLD)
                win.addnstr(row + 1, 6, (hint if enabled else "Nothing is running.")[: width - 8], width - 8, curses.A_DIM)
            win.addnstr(height - 1, 2, " up/down or 1-{} choose · Enter run · Esc close ".format(len(items)), width - 4, curses.A_DIM)
        except curses.error:
            pass
        win.refresh()

    def confirm(self, question):
        h, w = self.screen.getmaxyx()
        width = min(w - 4, max(44, len(question) + 6))
        win = curses.newwin(5, width, max(1, h // 2 - 2), max(1, (w - width) // 2))
        win.erase()
        draw_box(win, 5, width, "Confirm")
        top, left = max(1, h // 2 - 2), max(1, (w - width) // 2)
        try:
            win.addnstr(1, 2, question, width - 4, curses.A_BOLD)
            win.addnstr(3, 2, "[ Yes (y) ]", width - 4, curses.A_REVERSE | curses.A_BOLD)
            win.addnstr(3, 16, "[ Cancel ]", width - 18, curses.A_REVERSE)
        except curses.error:
            pass
        win.refresh()
        while True:
            self.screen.timeout(-1)
            key = self.screen.getch()
            self.screen.timeout(REFRESH_SEC * 1000)
            if key == curses.KEY_MOUSE:
                mouse = decode_mouse(read_after_kmous(self.screen))
            elif key != 27:
                return key in (ord("y"), ord("Y"))
            else:
                mouse = decode_mouse(read_escape(self.screen))
            if mouse is None:
                return False
            mx, my, kind = mouse
            if kind == "click":
                return my == top + 3 and left + 2 <= mx < left + 13

    def do(self, action):
        auto = self.model.auto
        if not auto:
            self.say("The Orca automation is missing; nothing to act on.")
            return
        if action == "check":
            self.check_now()
        elif action == "stop":
            if self.confirm("Stop the current check?"):
                self.stop_live()
        elif action == "restart":
            if self.confirm("Stop the current check and start a fresh one?"):
                if self.stop_live():
                    time.sleep(1)
                    self.check_now(quiet=True)
                    self.say("Restarted: the old check is stopped and a fresh one is starting.")
        elif action == "pause":
            if self.confirm("Pause the 10-minute checks? Nothing checks Slack until you resume."):
                _, err = orca_json(["automations", "edit", auto["id"], "--disabled"])
                self.say(err or "Paused. Resume from the actions menu (a).")
        elif action == "resume":
            _, err = orca_json(["automations", "edit", auto["id"], "--enabled"])
            self.say(err or "Resumed: checks run every 10 minutes again.")
        elif action == "switch":
            new = "claude" if auto.get("agentId") == "codex" else "codex"
            if self.confirm("Switch the coordinator to {}? Later checks start in {}.".format(new, new)):
                _, err = orca_json(["automations", "edit", auto["id"], "--provider", new])
                self.say(err or "Coordinator is now {}.".format(new))

    def check_now(self, quiet=False):
        auto = self.model.auto
        if not auto:
            return
        if self.model.live() and not quiet:
            self.say("A check is already running; it keeps reading Slack about every 9 minutes, so a new one is not needed.")
            return
        _, err = orca_json(["automations", "run", auto["id"]])
        if not quiet:
            self.say(err or "Check started. The 10-minute schedule keeps going.")

    def stop_live(self):
        live = self.model.live()
        if not live:
            self.say("Nothing is running.")
            return False
        term = live[0].get("terminal") or ""
        if term.startswith("term_"):
            _, err = orca_json(["terminal", "close", "--terminal", term])
            if err:
                self.say("Could not close the check's terminal: " + err)
                return False
        run([sys.executable, STATE_PY, "release", "--terminal", term])
        self.say("Stopped. Review workers keep going; the next check resumes them.")
        return True

    # details view
    def draw_details(self):
        s = self.screen
        s.erase()
        self.zones = []
        h, w = s.getmaxyx()
        checks = self.model.checks()
        self.put(0, 0, " Check summary ", curses.A_BOLD | curses.A_REVERSE)
        if not checks:
            lines = [("No checks yet.", curses.A_DIM)]
        else:
            self.refresh_slack()
            r, started, tr = checks[self.detail_index(checks)]
            shown = [i for row in self.check_rows(checks) for i in row["indices"]]
            now = datetime.now(KST)
            if tr is None:
                status = "no transcript"
            elif tr[2]:
                status = "failed"
            elif not tr[0]:
                status = "running for " + span((now - started).total_seconds()) if started else "running"
            else:
                status = "finished at {}{}".format(clock(tr[4]), " after " + span((tr[4] - started).total_seconds()) if tr[4] and started else "")
            where = "{} of {} in {}".format(shown.index(self.sel) + 1, len(shown), dict(FILTERS)[self.filter]) if self.sel in shown else "{} of {}".format(self.sel + 1, len(checks))
            self.put(0, 16, "check #{} at {} · {} · {}".format(r.get("runNumber"), clock(started), status, where), curses.A_BOLD)
            self.put(1, 1, "From: " + (tr[3] if tr else "no Codex transcript matched this check's start time"), curses.A_DIM)
            lines = self.detail_lines(started, tr, w - 3)
        room = h - 4
        self.scroll = max(0, min(self.scroll, len(lines) - room))
        for i, (line, attr) in enumerate(lines[self.scroll: self.scroll + room]):
            self.put(i + 3, 1, line, attr)
        if len(lines) > room:
            self.put(2, w - 24, "lines {}-{} of {}".format(self.scroll + 1, min(len(lines), self.scroll + room), len(lines)), curses.A_DIM)
        self.footer([("↑↓ or wheel scroll", None), ("← newer check", "newer"), ("→ older check", "older"), ("Esc back", "back")])
        s.refresh()

    def detail_lines(self, started, tr, width):
        """What a check did: its messages in the bot DM with the replies of yours it answered, then its own final message."""
        if tr is None:
            return [("No Codex transcript matched this check's start time, so there is nothing to show.", curses.A_DIM)]
        kind, text = self.classify(started, tr)
        out = [(line, curses.A_BOLD) for line in wrap("What it did: " + text, width)] + [("", 0)]
        if tr[2]:
            out += [(line, self.c["red"]) for line in wrap("FAILED: " + tr[2], width)] + [("", 0)]
        if tr[0] and claim_exit(tr):
            out += [("This check ended at once: another check was already running and holding the loop.", curses.A_DIM), ("", 0)]
        elif started:
            out += self.dm_lines(started, tr, width)
        out.append(("What the check reported (its final message)", curses.A_BOLD))
        body = tr[1] or ("(no message yet)" if not tr[0] else "(the check ended without a message)")
        for raw in body.splitlines():
            out += [("  " + line, 0) for line in wrap(raw.replace("**", ""), width - 2)]
        return out

    def dm_lines(self, started, tr, width):
        threads = self.dm_threads()[0]
        out = [("In the bot DM during this check", curses.A_BOLD)]
        if self.slack.error:
            return out + [("  " + self.slack.error, self.c["red"]), ("", 0)]
        if not self.slack.top:
            return out + [("  reading the bot DM…", curses.A_DIM), ("", 0)]
        end = (tr[4].timestamp() if tr[4] else time.time()) if tr[0] else time.time()
        groups = self.slack.events(started.timestamp() - 5, end + 5)
        if not groups:
            out.append(("  nothing was sent to the bot DM during this check", curses.A_DIM))
        day = started.date()
        stamp = lambda ts: datetime.fromtimestamp(float(ts), KST).strftime("%H:%M" if datetime.fromtimestamp(float(ts), KST).date() == day else "%b %d %H:%M")
        clock_width = max([len(stamp(e["ts"])) for _, events in groups for e in events] or [5])
        for root, events in groups:
            out.append(("  " + fit(threads.get(root, "A message outside the PR threads"), width - 2), curses.A_BOLD))
            for e in events:
                prefix = "    {:<{}}  {}  ".format(stamp(e["ts"]), clock_width, "You" if e["kind"] == "you" else "Bot")
                attr = (self.c["cyan"] | curses.A_BOLD) if e["kind"] == "you" else curses.A_DIM if e["kind"] == "items" else 0
                for j, line in enumerate(wrap(e["text"], max(20, width - cols(prefix)))):
                    out.append(((prefix if j == 0 else " " * cols(prefix)) + line, attr))
                if e["kind"] == "you":
                    mark = "no reply from this check yet" if e["ack"] == "unanswered" else ACK_MARK.get(e["ack"] or "")
                    if mark:
                        out.append((" " * cols(prefix) + mark, curses.A_DIM))
            out.append(("", 0))
        return out + [("", 0)] if not groups else out

    def loop(self):
        self.model.load()
        self.loaded_at = time.time()
        while True:
            if self.mode == "menu":
                self.draw_menu()
            elif self.mode == "details":
                self.draw_details()
            else:
                self.draw_main()
            # Redraw soon while the bot DM is being read, so its messages appear as soon as they arrive.
            self.screen.timeout(300 if self.slack.busy else REFRESH_SEC * 1000)
            key = self.screen.getch()
            if key == -1:
                if time.time() - self.loaded_at >= REFRESH_SEC:
                    self.model.load()
                    self.loaded_at = time.time()
                continue
            if key == curses.KEY_RESIZE:
                continue
            if key == curses.KEY_MOUSE:
                mouse = decode_mouse(read_after_kmous(self.screen))
                if mouse:
                    self.on_mouse(*mouse)
                continue
            if key == 27:
                seq = read_escape(self.screen)
                mouse = decode_mouse(seq)
                if mouse:
                    self.on_mouse(*mouse)
                    continue
                if seq:
                    continue
                key = 27
            if self.mode == "menu":
                items = self.actions()
                if key in (27, ord("a"), ord("q")):
                    self.mode = "main"
                elif key in (curses.KEY_UP, ord("k")):
                    self.menu_index = (self.menu_index - 1) % len(items)
                elif key in (curses.KEY_DOWN, ord("j")):
                    self.menu_index = (self.menu_index + 1) % len(items)
                elif ord("1") <= key < ord("1") + len(items):
                    self.menu_index = key - ord("1")
                elif key in (curses.KEY_ENTER, 10, 13):
                    action, _, _, enabled = items[self.menu_index]
                    self.mode = "main"
                    if enabled:
                        self.draw_main()
                        self.do(action)
                        self.model.load()
                    else:
                        self.say("Nothing is running, so there is nothing to stop.")
                continue
            if self.mode == "details":
                if key in (27, ord("q"), curses.KEY_ENTER, 10, 13):
                    self.back_to_main()
                elif key in (curses.KEY_LEFT, ord("h")):
                    self.step(-1)
                elif key in (curses.KEY_RIGHT, ord("l")):
                    self.step(1)
                elif key in (curses.KEY_DOWN, ord("j")):
                    self.scroll += 1
                elif key in (curses.KEY_UP, ord("k")):
                    self.scroll = max(0, self.scroll - 1)
                elif key == curses.KEY_NPAGE:
                    self.scroll += 10
                elif key == curses.KEY_PPAGE:
                    self.scroll = max(0, self.scroll - 10)
                continue
            if key == ord("q"):
                return
            if key in (curses.KEY_UP, ord("k")):
                self.move(-1)
            elif key in (curses.KEY_DOWN, ord("j")):
                self.move(1)
            elif key in (curses.KEY_ENTER, 10, 13):
                self.open_selected()
            elif key == ord("f"):
                names = [name for name, _ in FILTERS]
                self.filter = names[(names.index(self.filter) + 1) % len(names)]
                self.offset = 0
            elif key == ord("a"):
                self.mode = "menu"
                self.menu_index = 0


MOUSE_ON = "\033[?1000h\033[?1006h"    # report button presses, in the SGR format
MOUSE_OFF = "\033[?1006l\033[?1000l"
SGR_MOUSE = re.compile(r"\[<(\d+);(\d+);(\d+)([Mm])$")


def read_escape(screen):
    """After an ESC, collect the rest of an escape sequence that arrives at once ("" for a lone ESC)."""
    screen.timeout(30)
    chars = []
    while len(chars) < 32:
        c = screen.getch()
        if c == -1:
            break
        chars.append(chr(c) if c < 256 else "")
        seq = "".join(chars)
        if SGR_MOUSE.match(seq) or (seq.startswith("[M") and len(seq) == 5):
            break
    screen.timeout(REFRESH_SEC * 1000)
    return "".join(chars)


def read_after_kmous(screen):
    """The terminal database may claim the start of a mouse report (\\E[M or \\E[<) and hand back KEY_MOUSE; read the
    rest of the report that is still waiting and rebuild the whole sequence."""
    screen.timeout(30)
    chars = []
    while len(chars) < 32:
        c = screen.getch()
        if c == -1:
            break
        chars.append(chr(c) if c < 256 else "")
        rest = "".join(chars)
        if re.match(r"\d+;\d+;\d+[Mm]$", rest) or (len(rest) == 3 and not rest[0].isdigit()):
            break
    screen.timeout(REFRESH_SEC * 1000)
    rest = "".join(chars)
    return ("[<" + rest) if re.match(r"\d+;\d+;\d+[Mm]$", rest) else ("[M" + rest)


def decode_mouse(seq):
    """(x, y, kind) for a mouse report: kind is click, wheel_up, wheel_down, or None for releases and motion."""
    m = SGR_MOUSE.match(seq)
    if m:
        b, x, y, pressed = int(m.group(1)), int(m.group(2)) - 1, int(m.group(3)) - 1, m.group(4) == "M"
    elif seq.startswith("[M") and len(seq) == 5:
        b, x, y = ord(seq[2]) - 32, ord(seq[3]) - 33, ord(seq[4]) - 33
        pressed = (b & 3) != 3
    else:
        return None
    if b & 64:
        return x, y, "wheel_down" if b & 1 else "wheel_up"
    if b & 32 or not pressed or (b & 3) != 0:
        return x, y, None
    return x, y, "click"


def _on_mouse(self, x, y, kind):
    """Clicks and the wheel, in whichever view is showing."""
    if kind in ("wheel_up", "wheel_down"):
        step = -1 if kind == "wheel_up" else 1
        if self.mode == "details":
            self.scroll = max(0, self.scroll + step * 3)
        elif self.mode == "main":
            self.move(step)
        return
    if kind != "click":
        return
    action, value = self.hit(y, x)
    if self.mode == "menu":
        if action == "menu_item":
            items = self.actions()
            self.menu_index = value
            act, _, _, enabled = items[value]
            self.mode = "main"
            if enabled:
                self.draw_main()
                self.do(act)
                self.model.load()
            else:
                self.say("Nothing is running, so there is nothing to stop.")
        elif action == "menu_close":
            self.mode = "main"
        return
    if action == "select" and value[0] == "ask":
        # A waiting question exists only to be answered, so one click goes straight to its thread in Slack.
        self.cur = value
        self.open_selected()
    elif action == "select":
        # One click selects the row; a second click on it within DOUBLE_CLICK_SEC opens it, like Enter.
        now = time.time()
        double = self.last_click[0] == value and now - self.last_click[1] < DOUBLE_CLICK_SEC
        self.cur = value
        self.last_click = (None, 0) if double else (value, now)
        if double:
            self.open_selected()
    elif action == "open":
        self.open_selected()
    elif action == "filter":
        self.filter, self.offset = value, 0
    elif action == "cycle_filter":
        names = [name for name, _ in FILTERS]
        self.filter, self.offset = names[(names.index(self.filter) + 1) % len(names)], 0
    elif action == "menu":
        self.mode = "menu"
        self.menu_index = 0
    elif action == "quit":
        raise SystemExit(0)
    elif action == "newer":
        self.step(-1)
    elif action == "older":
        self.step(1)
    elif action == "back":
        self.back_to_main()


Dashboard.on_mouse = _on_mouse


def snapshot():
    m = Model(Transcripts())
    m.load()
    level, text = m.health()
    auto = m.auto or {}
    live = m.live()
    print("loop:", level.upper(), "-", text)
    print("next check:", clock(kst(auto.get("nextRunAt"))) if auto.get("enabled") else "paused", "| coordinator:", auto.get("agentId"), "| current check:", "running" if live else "none")
    print(watcher_status()[1])
    view = Dashboard.__new__(Dashboard)  # the check list without a screen: same categories as the TUI
    view.model, view.slack, view.kind_cache, view.filter = m, SlackLog(), {}, "did"
    _, _, channel = view.dm_threads()
    oldest = min((c[1] for c in m.checks() if c[1]), default=datetime.now(KST))
    if channel:
        view.slack._fetch(channel, oldest.timestamp() - 3600)
    rows = view.check_rows(m.checks())
    print("checks: " + ", ".join("{} {}".format(view.counts[name], label.lower()) for name, label in FILTERS if name != "all") + " (of the last {})".format(view.counts["all"]))
    for row in rows[:8]:
        print("check", clock(row["started"]), KIND_MARK[row["kind"]], row["text"][:150], ("(" + row["trigger"] + ")") if row["trigger"] else "")
    for pr, r in ((m.state or {}).get("reviews") or {}).items():
        if r.get("status") in LIVE_REVIEW + WAITING + TRACKED:
            status = str(r.get("status"))
            print("review #{}".format(pr.split("#")[-1]), STATUS_LABEL.get(status, status), "-", (r.get("title") or "")[:70])
    for a in waiting_asks(m.state or {}, lambda pr, r: {"channel": None, "message": None, "thread": None, "web": r.get("url")}):
        print("waiting on you:", a["what"], "| reply", a["reply"], "in", a["target"]["web"])
    for err in m.errors:
        print("error:", err)


def main():
    if "--once" in sys.argv:
        snapshot()
        return 0
    os.environ.setdefault("ESCDELAY", "25")
    try:
        curses.wrapper(lambda screen: Dashboard(screen).loop())
    finally:
        sys.stdout.write(MOUSE_OFF)
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
