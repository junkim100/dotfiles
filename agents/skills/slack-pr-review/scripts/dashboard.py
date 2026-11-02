#!/usr/bin/env python3
"""Terminal dashboard for the slack-pr-review loop.

The screen is a status view first: the loop is meant to stay running, so no single key press acts on it. Up and down select a check in the Recent checks list and Enter opens that check's full summary (left and right step to the previous or next check from there). Every action lives in the actions menu behind `a`: check now (one check right away while the 10-minute schedule keeps going), stop or restart the current check, pause or resume the schedule, and switch the coordinator; each one that interrupts or changes the loop asks to confirm. `q` quits.

It shows the loop's health (running on schedule, paused, or failing, with the reason), the current check, every review in progress, waiting on the user, or tracked, the questions waiting in the bot DM, and the recent checks with each one's summary or error from its Codex transcript. Stopping a check closes its terminal and releases the loop claim; review workers keep going and the next check resumes them.

Standard library only (curses), so it runs on the macOS system Python. `--once` prints a plain-text snapshot instead.
"""

import curses
import glob
import json
import os
import subprocess
import sys
import time
import unicodedata
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
STATE_PY = os.path.join(HERE, "state.py")
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
        last, done, error = None, False, None
        with open(path, errors="replace") as f:
            for line in f:
                if '"task_complete"' not in line and '"agent_message"' not in line:
                    continue
                try:
                    payload = json.loads(line).get("payload", {})
                except ValueError:
                    continue
                if payload.get("type") == "task_complete":
                    done = True
                    last = payload.get("last_agent_message") or last
                    error = (payload.get("error") or {}).get("message") or error
                elif payload.get("type") == "agent_message":
                    last = payload.get("message") or last
        result = (done, (last or "").strip(), error, path)
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


def claim_exit(text):
    """True when a check ended at once because another check held the loop claim."""
    t = (text or "").lower()
    return ("claim" in t or "실행권" in text or "already" in t) and ("another" in t or "다른" in text) and len(t) < 600


def short_error(error):
    if not error:
        return ""
    if "usage limit" in error.lower():
        until = error.split("try again at", 1)[1].strip().rstrip(".") if "try again at" in error else ""
        return "out of usage" + (" until " + until if until else "")
    return error[:120]


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
                self.runs = (runs or {}).get("runs", [])[:40]
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
        self.mode = "main"
        self.menu_index = 0
        self.scroll = 0
        self.sel = 0
        self.offset = 0
        self.toast = ""
        self.toast_until = 0
        curses.curs_set(0)
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

    def say(self, text):
        self.toast = text
        self.toast_until = time.time() + 12

    # main view
    def draw_main(self):
        s = self.screen
        s.erase()
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
            ("Last check", "{} {}".format(clock(last[1]), "failed" if last[2][2] else "ok") if last else "-", (self.c["red"] if last[2][2] else self.c["green"]) if last else 0),
            ("Coordinator", "{}{}".format(auto.get("agentId") or "?", ", out of usage" if level == "failing" and "usage" in text else ""), self.c["red"] if level == "failing" and "usage" in text else 0),
        ]
        for i, (title, value, attr) in enumerate(cards):
            x = 1 + i * col
            self.put(y, x, title, curses.A_DIM)
            self.put(y + 1, x, value[: col - 2], attr | curses.A_BOLD)
        y += 3
        self.put(y, 1, "Reviewers: Codex, Claude Code, Kimi (effort {}) for big PRs; one reviewer for small PRs".format(m.kimi_effort), curses.A_DIM)
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
        y = self.rule(y, "Reviews")
        budget = max(3, h - y - 13)
        for pr, r, status, updated in rows[:budget]:
            attr = self.c["green"] if status in LIVE_REVIEW else self.c["yellow"] if status in WAITING else self.c["blue"] if status in TRACKED else curses.A_DIM
            dot = "●" if status in LIVE_REVIEW + WAITING + TRACKED else "○"
            self.put(y, 1, dot, attr)
            self.put(y, 3, "#{:<6}".format(pr.split("#")[-1]), curses.A_BOLD)
            self.put(y, 11, "{:<19}".format(STATUS_LABEL.get(status, status)), attr)
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
            self.put(y, 31, fit(title, max(10, w - 31 - cols(detail) - 4)))
            self.put(y, max(31, w - len(detail) - 2), detail, curses.A_DIM if status not in LIVE_REVIEW else attr)
            y += 1
        if not rows:
            self.put(y, 3, "nothing in progress", curses.A_DIM)
            y += 1
        if len(rows) > budget:
            self.put(y, 3, "+{} more".format(len(rows) - budget), curses.A_DIM)
            y += 1
        y += 1

        asks = []
        for key, msg in (st.get("messages") or {}).items():
            a = msg.get("ask") or {}
            if a.get("status") == "asked":
                prs = ", ".join("#" + p.split("#")[-1] for p in msg.get("prs") or []) or "?"
                asks.append((kst(a.get("asked_at")), "{}: review it? (asked by {})".format(prs, msg.get("from_name") or "?")))
        for pr, r in reviews.items():
            a = r.get("ask") or {}
            if a.get("status") == "asked":
                what = {"post_first": "post the review?", "post_fix": "post the fix-check follow-up?"}.get(a.get("kind"), "reply needed")
                asks.append((kst(a.get("asked_at")), "#{}: {}".format(pr.split("#")[-1], what)))
        y = self.rule(y, "Waiting on you" + ("  ({})".format(len(asks)) if asks else ""))
        for at, line in sorted(asks, key=lambda a: a[0] or now)[:4]:
            self.put(y, 1, "●", self.c["yellow"])
            self.put(y, 3, line)
            self.put(y, w - 14, ago(at), curses.A_DIM)
            y += 1
        if not asks:
            self.put(y, 3, "nothing; reply in the bot DM thread when something shows up here", curses.A_DIM)
            y += 1
        y += 1

        self.sel = max(0, min(self.sel, len(checks) - 1))
        rows = max(3, h - y - 4)
        if self.sel < self.offset:
            self.offset = self.sel
        elif self.sel >= self.offset + rows:
            self.offset = self.sel - rows + 1
        y = self.rule(y, "Recent checks  ({} of {})".format(self.sel + 1 if checks else 0, len(checks)))
        for i, (r, started, tr) in enumerate(checks[self.offset: self.offset + rows], start=self.offset):
            if tr is None:
                mark, attr, text = "?", curses.A_DIM, "no transcript"
            elif tr[2]:
                mark, attr, text = "✗", self.c["red"], "failed: " + short_error(tr[2])
            elif not tr[0]:
                mark, attr, text = "…", self.c["green"], "running"
            elif claim_exit(tr[1]):
                mark, attr, text = "–", curses.A_DIM, "skipped: another check was already running"
            else:
                mark, attr, text = "✓", self.c["green"], headline(tr[1], w - 20) or "no summary"
            if i == self.sel:
                self.put(y, 0, " " * (w - 1), curses.A_REVERSE)
                self.put(y, 0, "▶", curses.A_REVERSE | curses.A_BOLD)
                self.put(y, 1, mark, curses.A_REVERSE | curses.A_BOLD)
                self.put(y, 3, clock(started), curses.A_REVERSE)
                self.put(y, 10, fit(text, w - 12), curses.A_REVERSE)
            else:
                self.put(y, 1, mark, attr)
                self.put(y, 3, clock(started), curses.A_DIM)
                self.put(y, 10, fit(text, w - 12), attr if mark != "✓" else 0)
            y += 1

        if m.errors:
            self.put(h - 2, 1, m.errors[0], self.c["red"])
        elif self.toast and time.time() < self.toast_until:
            self.put(h - 2, 1, self.toast, self.c["cyan"])
        footer = " ↑↓ select a check    Enter open it    a actions    q quit "
        self.put(h - 1, 0, " " * (w - 1), curses.A_REVERSE)
        self.put(h - 1, 0, footer, curses.A_REVERSE)
        self.put(h - 1, w - 26, "refreshes every {}s".format(REFRESH_SEC), curses.A_REVERSE | curses.A_DIM)
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
        try:
            win.addnstr(1, 2, question, width - 4, curses.A_BOLD)
            win.addnstr(3, 2, "y yes    any other key: cancel", width - 4, curses.A_DIM)
        except curses.error:
            pass
        win.refresh()
        self.screen.timeout(-1)
        key = self.screen.getch()
        self.screen.timeout(REFRESH_SEC * 1000)
        return key in (ord("y"), ord("Y"))

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
        h, w = s.getmaxyx()
        checks = self.model.checks()
        self.put(0, 0, " Check summary ", curses.A_BOLD | curses.A_REVERSE)
        if not checks:
            self.put(2, 1, "No checks yet.", curses.A_DIM)
        else:
            self.sel = max(0, min(self.sel, len(checks) - 1))
            r, started, tr = checks[self.sel]
            status = "no transcript" if tr is None else "failed" if tr[2] else "still running" if not tr[0] else "finished"
            self.put(0, 16, "check #{} at {} · {} · {} of {}".format(r.get("runNumber"), clock(started), status, self.sel + 1, len(checks)), curses.A_BOLD)
            self.put(1, 1, "From: " + (tr[3] if tr else "no Codex transcript matched this check's start time"), curses.A_DIM)
            body = "" if tr is None else ("FAILED: " + tr[2] + "\n\n" if tr[2] else "") + (tr[1] or ("(no message yet)" if not tr[0] else "(the check ended without a message)"))
            lines = []
            for raw in body.splitlines():
                raw = raw.replace("**", "")
                while len(raw) > w - 3:
                    lines.append(raw[: w - 3])
                    raw = raw[w - 3:]
                lines.append(raw)
            for i, line in enumerate(lines[self.scroll: self.scroll + h - 4]):
                self.put(i + 3, 1, line, self.c["red"] if line.startswith("FAILED") else 0)
        self.put(h - 1, 0, " " * (w - 1), curses.A_REVERSE)
        self.put(h - 1, 0, " ↑↓ scroll    ← newer check    → older check    Esc back ", curses.A_REVERSE)
        s.refresh()

    def loop(self):
        self.model.load()
        while True:
            if self.mode == "menu":
                self.draw_menu()
            elif self.mode == "details":
                self.draw_details()
            else:
                self.draw_main()
            key = self.screen.getch()
            if key == -1:
                self.model.load()
                continue
            if key == curses.KEY_RESIZE:
                continue
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
                    self.mode = "main"
                elif key in (curses.KEY_LEFT, ord("h")):
                    self.sel = max(0, self.sel - 1)
                    self.scroll = 0
                elif key in (curses.KEY_RIGHT, ord("l")):
                    self.sel = min(len(self.model.runs) - 1, self.sel + 1)
                    self.scroll = 0
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
                self.sel = max(0, self.sel - 1)
            elif key in (curses.KEY_DOWN, ord("j")):
                self.sel = min(len(self.model.runs) - 1, self.sel + 1)
            elif key in (curses.KEY_ENTER, 10, 13):
                self.mode = "details"
                self.scroll = 0
            elif key == ord("a"):
                self.mode = "menu"
                self.menu_index = 0


def snapshot():
    m = Model(Transcripts())
    m.load()
    level, text = m.health()
    auto = m.auto or {}
    live = m.live()
    print("loop:", level.upper(), "-", text)
    print("next check:", clock(kst(auto.get("nextRunAt"))) if auto.get("enabled") else "paused", "| coordinator:", auto.get("agentId"), "| current check:", "running" if live else "none")
    for r, started, tr in m.checks()[:5]:
        status = "no transcript" if tr is None else ("failed: " + short_error(tr[2])) if tr[2] else "running" if not tr[0] else headline(tr[1], 110)
        print("check", clock(started), status)
    for pr, r in ((m.state or {}).get("reviews") or {}).items():
        if r.get("status") in LIVE_REVIEW + WAITING + TRACKED:
            status = str(r.get("status"))
            print("review #{}".format(pr.split("#")[-1]), STATUS_LABEL.get(status, status), "-", (r.get("title") or "")[:70])
    for err in m.errors:
        print("error:", err)


def main():
    if "--once" in sys.argv:
        snapshot()
        return 0
    curses.wrapper(lambda screen: Dashboard(screen).loop())
    return 0


if __name__ == "__main__":
    sys.exit(main())
