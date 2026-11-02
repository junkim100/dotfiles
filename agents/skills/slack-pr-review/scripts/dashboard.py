#!/usr/bin/env python3
"""Terminal dashboard for the slack-pr-review loop.

Shows whether the scheduled loop is enabled, whether a run is live and what it is doing, every review in flight or tracked, the questions waiting for the user, and the last runs with each run's own summary. Keys: s resume the schedule, p pause it, n run now, x stop the live run, R restart (stop the live run, then run now), c switch the coordinator between Codex and Claude Code (for when one is out of usage), Enter or l show the newest run's full summary, r refresh, q quit. A run that failed (for example on the coordinator's usage limit) is shown in red with its error. Stopping a run closes its terminal and releases the loop claim; review workers keep going and the next run picks them up.

Standard library only (curses), so it runs on the macOS system Python. Reads the loop state through state.py's file, Orca through the `orca` CLI, and run summaries from the Codex session transcripts the runs leave.
"""

import curses
import glob
import json
import os
import subprocess
import sys
import time
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


def state():
    out, err = run([sys.executable, STATE_PY, "show"])
    if out is None:
        return {}, err
    return json.loads(out), None


def kst(ms_or_iso):
    if not ms_or_iso:
        return None
    if isinstance(ms_or_iso, (int, float)) or str(ms_or_iso).isdigit():
        return datetime.fromtimestamp(int(ms_or_iso) / 1000, KST)
    try:
        return datetime.fromisoformat(str(ms_or_iso).replace("Z", "+00:00")).astimezone(KST)
    except ValueError:
        return None


def hm(dt, with_day=False):
    if dt is None:
        return "-"
    today = datetime.now(KST).date()
    if with_day or dt.date() != today:
        return dt.strftime("%m-%d %H:%M")
    return dt.strftime("%H:%M:%S")


def ago(dt):
    if dt is None:
        return "-"
    sec = int((datetime.now(KST) - dt).total_seconds())
    if sec < 0:
        return "in " + ago_text(-sec)
    return ago_text(sec) + " ago"


def ago_text(sec):
    if sec < 90:
        return "{}s".format(sec)
    if sec < 5400:
        return "{}m".format(sec // 60)
    if sec < 172800:
        return "{}h{:02d}m".format(sec // 3600, (sec % 3600) // 60)
    return "{}d".format(sec // 86400)


class Summaries:
    """Final messages of the loop's Codex runs, matched to Orca runs by start time."""

    def __init__(self):
        self.cache = {}

    def files(self, since):
        found = []
        for root in SESSION_GLOBS:
            for base in glob.glob(root):
                for day in range(0, 3):
                    d = since - timedelta(days=day)
                    found += glob.glob(os.path.join(base, d.strftime("%Y/%m/%d"), "rollout-*.jsonl"))
        return found

    def for_run(self, started):
        """Return (finished, text, is_loop_run, path, error) for the transcript that began within 90 s of the run's start."""
        if started is None:
            return None
        best = None
        for path in self.files(started):
            name = os.path.basename(path)[len("rollout-"):len("rollout-") + 19]
            try:
                t = datetime.strptime(name, "%Y-%m-%dT%H-%M-%S").replace(tzinfo=KST)
            except ValueError:
                continue
            gap = (t - started).total_seconds()
            if -5 <= gap <= 90 and (best is None or abs(gap) < best[0]):
                best = (abs(gap), path)
        if best is None:
            return None
        return self.parse(best[1])

    def parse(self, path):
        mtime = os.path.getmtime(path)
        hit = self.cache.get(path)
        if hit and hit[0] == mtime:
            return hit[1]
        last, done, slack, error = None, False, False, None
        try:
            with open(path, errors="replace") as f:
                for line in f:
                    if '"$slack-pr-review' in line or "slack-pr-review" in line[:4000]:
                        slack = True
                    if '"task_complete"' not in line and '"agent_message"' not in line:
                        continue
                    try:
                        p = json.loads(line).get("payload", {})
                    except ValueError:
                        continue
                    if p.get("type") == "task_complete":
                        done = True
                        last = p.get("last_agent_message") or last
                        error = (p.get("error") or {}).get("message") or error
                    elif p.get("type") == "agent_message":
                        last = p.get("message") or last
        except OSError:
            return None
        result = (done, (last or "").strip(), slack, path, error)
        self.cache[path] = (mtime, result)
        return result


def first_line(text, width):
    for line in (text or "").splitlines():
        line = line.strip().lstrip("#").strip().replace("**", "")
        if line and not line.startswith("|") and not line.startswith("---"):
            return line[:width]
    return ""


class Dashboard:
    def __init__(self, screen):
        self.screen = screen
        self.summaries = Summaries()
        self.message = ""
        self.view = "main"
        self.detail_scroll = 0
        self.data = {}
        curses.curs_set(0)
        curses.use_default_colors()
        for i, color in enumerate([curses.COLOR_GREEN, curses.COLOR_YELLOW, curses.COLOR_RED, curses.COLOR_CYAN, curses.COLOR_MAGENTA], start=1):
            curses.init_pair(i, color, -1)
        self.GREEN, self.YELLOW, self.RED, self.CYAN, self.MAGENTA = (curses.color_pair(i) for i in range(1, 6))
        self.screen.timeout(REFRESH_SEC * 1000)

    def load(self):
        data = {"errors": []}  # type: dict
        listing, err = orca_json(["automations", "list"])
        auto = None
        if listing is not None:
            items = listing.get("automations", listing) if isinstance(listing, dict) else listing
            auto = next((a for a in items if a.get("name") == AUTOMATION_NAME), None)
        else:
            data["errors"].append("orca: " + str(err))
        if auto:
            shown, err = orca_json(["automations", "show", "--id", auto["id"]])
            if shown is not None:
                auto = shown.get("automation", shown)
            runs, err = orca_json(["automations", "runs", "--id", auto["id"]])
            data["runs"] = (runs or {}).get("runs", [])[:8] if runs else []
        data["auto"] = auto
        st, err = state()
        if err:
            data["errors"].append("state: " + err)
        data["state"] = st
        try:
            with open(os.path.expanduser("~/.kimi-code/config.toml")) as f:
                text = f.read()
            effort = None
            in_thinking = False
            for line in text.splitlines():
                if line.strip().startswith("["):
                    in_thinking = line.strip() == "[thinking]"
                elif in_thinking and line.strip().startswith("effort"):
                    effort = line.split("=", 1)[1].strip().strip('"')
            data["kimi_effort"] = effort or "default"
        except OSError:
            data["kimi_effort"] = "unknown"
        self.data = data

    def live_run(self):
        st = self.data.get("state") or {}
        owner = st.get("owner")
        if not owner:
            return None
        beat = kst(owner.get("heartbeat"))
        if beat is None or (datetime.now(KST) - beat).total_seconds() > 1800:
            return None
        return owner, beat

    # drawing
    def put(self, y, x, text, attr=0):
        h, w = self.screen.getmaxyx()
        if y >= h or x >= w:
            return
        try:
            self.screen.addnstr(y, x, text, max(0, w - x - 1), attr)
        except curses.error:
            pass

    def section(self, y, title):
        self.put(y, 0, title, curses.A_BOLD | self.CYAN)
        return y + 1

    def draw_main(self):
        s = self.screen
        s.erase()
        h, w = s.getmaxyx()
        auto = self.data.get("auto")
        st = self.data.get("state") or {}
        now = datetime.now(KST)
        y = 0
        self.put(y, 0, "PR Review Loop", curses.A_BOLD)
        self.put(y, 16, now.strftime("%Y-%m-%d %H:%M:%S KST"))
        y += 2
        if auto:
            on = auto.get("enabled")
            self.put(y, 0, "Schedule  ")
            self.put(y, 10, "ENABLED" if on else "PAUSED", curses.A_BOLD | (self.GREEN if on else self.YELLOW))
            nxt = kst(auto.get("nextRunAt"))
            self.put(y, 19, "every 10 min ({})  next {} ({})".format(auto.get("rrule"), hm(nxt), ago(nxt)) if on else "no new runs start until resumed")
        else:
            self.put(y, 0, "Schedule  automation '{}' not found".format(AUTOMATION_NAME), self.RED)
        y += 1
        live = self.live_run()
        self.put(y, 0, "Run now   ")
        if live:
            owner, beat = live
            self.put(y, 10, "RUNNING", curses.A_BOLD | self.GREEN)
            self.put(y, 19, "heartbeat {} ({})  terminal {}".format(hm(beat), ago(beat), (owner.get("terminal") or "")[:18]))
        else:
            self.put(y, 10, "idle", curses.A_DIM)
            runs = self.data.get("runs") or []
            if runs:
                last = kst(runs[0].get("startedAt") or runs[0].get("scheduledFor"))
                self.put(y, 19, "last run started {} ({})".format(hm(last), ago(last)))
        y += 1
        runs = self.data.get("runs") or []
        newest = self.summaries.for_run(kst(runs[0].get("startedAt"))) if runs else None
        self.put(y, 0, "Coordinator ")
        self.put(y, 12, "{}".format((auto or {}).get("agentId") or "?"), curses.A_BOLD)
        if newest and newest[4]:
            self.put(y, 20, "LAST RUN FAILED: " + newest[4], curses.A_BOLD | self.RED)
        y += 1
        limits = []
        for name, value in sorted((st.get("harness_limits") or {}).items()):
            until = kst(value.get("until"))
            if until and until > now:
                limits.append("{} out until {}".format(name, hm(until)))
        self.put(y, 0, "Harness   ")
        self.put(y, 10, "codex, claude, kimi (kimi effort {}){}".format(self.data.get("kimi_effort"), "  |  " + "; ".join(limits) if limits else ""), self.RED if limits else 0)
        y += 2

        reviews = st.get("reviews") or {}
        rows = []
        for pr, r in reviews.items():
            status = r.get("status", "")
            updated = kst(r.get("updated_at"))
            if status in LIVE_REVIEW + WAITING + TRACKED or (updated and (now - updated).days < 3):
                rows.append((pr, r, status, updated))
        order = {s_: i for i, s_ in enumerate(LIVE_REVIEW + WAITING + TRACKED)}
        rows.sort(key=lambda x: (order.get(x[2], 99), -(x[3].timestamp() if x[3] else 0)))
        y = self.section(y, "Reviews  (in flight, waiting on you, tracked, and changed in the last 3 days)")
        self.put(y, 2, "{:<8} {:<15} {:<9} {:<44} {}".format("PR", "status", "head", "title", "progress / updated"), curses.A_DIM)
        y += 1
        for pr, r, status, updated in rows[: max(3, (h - 24) // 2)]:
            color = self.GREEN if status in LIVE_REVIEW else self.YELLOW if status in WAITING else self.MAGENTA if status in TRACKED else curses.A_DIM
            num = "#" + pr.split("#")[-1]
            title = (r.get("title") or "")[:44]
            progress = []
            for stage, wk in (r.get("workers") or {}).items():
                if status in LIVE_REVIEW:
                    mark = {"running": "~", "succeeded": "ok", "done": "ok", "failed": "x"}.get(wk.get("state"), wk.get("state") or "?")
                    progress.append("{}:{}".format(stage.replace("review-", "r"), mark))
            info = " ".join(progress) if progress else "updated " + ago(updated)
            self.put(y, 2, "{:<8} ".format(num))
            self.put(y, 11, "{:<15}".format(status), color)
            self.put(y, 27, "{:<9} {:<44} {}".format((r.get("head") or "")[:7], title, info))
            y += 1
        if not rows:
            self.put(y, 2, "none", curses.A_DIM)
            y += 1
        y += 1

        asks = []
        for key, m in (st.get("messages") or {}).items():
            a = m.get("ask") or {}
            if a.get("status") == "asked":
                asks.append(("question", ",".join(m.get("prs") or []) or "-", kst(a.get("asked_at")), m.get("from_name") or ""))
        for pr, r in reviews.items():
            a = r.get("ask") or {}
            if a.get("status") == "asked":
                asks.append(({"post_first": "post review?", "post_fix": "post fix check?"}.get(a.get("kind"), a.get("kind") or "ask"), pr, kst(a.get("asked_at")), ""))
        y = self.section(y, "Waiting on you  (reply in the bot DM thread)")
        for kind, pr, at, who in sorted(asks, key=lambda a: a[2] or now):
            self.put(y, 2, "{:<16} {:<30} asked {} {}".format(kind, pr.replace("UpstageAI/solar-system", ""), ago(at), ("by " + who) if who else ""), self.YELLOW)
            y += 1
        if not asks:
            self.put(y, 2, "nothing", curses.A_DIM)
            y += 1
        y += 1

        y = self.section(y, "Last runs  (Enter: newest run's full summary)")
        for x in (self.data.get("runs") or [])[: max(2, h - y - 4)]:
            started = kst(x.get("startedAt"))
            summary = self.summaries.for_run(started)
            if summary is None:
                text, attr = "(no transcript found)", curses.A_DIM
            elif summary[4]:
                text, attr = "FAILED: " + summary[4], self.RED
            elif not summary[0]:
                text, attr = "running...", self.GREEN
            else:
                text, attr = first_line(summary[1], w - 40) or "(empty summary)", 0
            self.put(y, 2, "#{:<5} {} {:<10} ".format(x.get("runNumber", ""), hm(started), (x.get("status") or "")[:10]))
            self.put(y, 31, text, attr)
            y += 1

        for err in self.data.get("errors") or []:
            self.put(h - 3, 0, err[: w - 1], self.RED)
        self.put(h - 2, 0, self.message[: w - 1], self.YELLOW)
        self.put(h - 1 if h > 1 else 0, 0, "s resume  p pause  n run now  x stop live run  R restart  c switch coordinator  Enter summary  r refresh  q quit", curses.A_REVERSE)
        s.refresh()

    def newest_summary(self):
        for x in self.data.get("runs") or []:
            summary = self.summaries.for_run(kst(x.get("startedAt")))
            if summary and (summary[1] or summary[4]):
                return x, summary
        return None, None

    def draw_detail(self):
        s = self.screen
        s.erase()
        h, w = s.getmaxyx()
        x, summary = self.newest_summary()
        if not summary:
            self.put(0, 0, "No run summary found yet.")
        else:
            head = "Run #{} started {}{}".format(x.get("runNumber"), hm(kst(x.get("startedAt")), True), "" if summary[0] else "  (still running; last message so far)")
            self.put(0, 0, head, curses.A_BOLD)
            lines = []
            body = summary[1] or ""
            if summary[4]:
                body = "FAILED: " + summary[4] + ("\n\n" + body if body else "")
            for raw in body.splitlines():
                raw = raw.replace("**", "")
                while len(raw) > w - 2:
                    lines.append(raw[: w - 2])
                    raw = raw[w - 2:]
                lines.append(raw)
            view = lines[self.detail_scroll: self.detail_scroll + h - 3]
            for i, line in enumerate(view):
                self.put(i + 2, 0, line)
        self.put(h - 1, 0, "up/down scroll  Esc or q back", curses.A_REVERSE)
        s.refresh()

    # actions
    def confirm(self, question):
        self.message = question + "  [y/N]"
        self.draw_main()
        self.screen.timeout(-1)
        key = self.screen.getch()
        self.screen.timeout(REFRESH_SEC * 1000)
        return key in (ord("y"), ord("Y"))

    def set_enabled(self, on):
        auto = self.data.get("auto")
        if not auto:
            self.message = "automation not found"
            return
        _, err = orca_json(["automations", "edit", auto["id"], "--enabled" if on else "--disabled"])
        self.message = err or ("Schedule resumed: runs start every 10 minutes again." if on else "Schedule paused: no new runs start. A live run keeps going; x stops it.")

    def run_now(self):
        auto = self.data.get("auto")
        if not auto:
            self.message = "automation not found"
            return
        _, err = orca_json(["automations", "run", auto["id"]])
        self.message = err or "Run requested. If a run is still live, the new one exits at the loop claim."

    def switch_coordinator(self):
        auto = self.data.get("auto")
        if not auto:
            self.message = "automation not found"
            return
        new = "claude" if auto.get("agentId") == "codex" else "codex"
        if not self.confirm("Switch the coordinator from {} to {}? Later runs start in {}.".format(auto.get("agentId"), new, new)):
            self.message = "Coordinator unchanged."
            return
        _, err = orca_json(["automations", "edit", auto["id"], "--provider", new])
        self.message = err or "Coordinator is now {}. The next run starts with it.".format(new)

    def stop_live(self):
        live = self.live_run()
        if not live:
            self.message = "No live run to stop."
            return False
        owner, _ = live
        term = owner.get("terminal") or ""
        if term.startswith("term_"):
            _, err = orca_json(["terminal", "close", "--terminal", term])
            if err:
                self.message = "Could not close the run's terminal: " + err
        run([sys.executable, STATE_PY, "release", "--terminal", term])
        self.message = "Stopped the live run and released the loop claim. Review workers keep running; the next run resumes them."
        return True

    def loop(self):
        self.load()
        while True:
            if self.view == "main":
                self.draw_main()
            else:
                self.draw_detail()
            key = self.screen.getch()
            if key == -1:
                self.load()
                continue
            if self.view == "detail":
                if key in (27, ord("q"), ord("l"), curses.KEY_ENTER, 10, 13):
                    self.view = "main"
                elif key == curses.KEY_DOWN:
                    self.detail_scroll += 1
                elif key == curses.KEY_UP:
                    self.detail_scroll = max(0, self.detail_scroll - 1)
                elif key == curses.KEY_NPAGE:
                    self.detail_scroll += 10
                elif key == curses.KEY_PPAGE:
                    self.detail_scroll = max(0, self.detail_scroll - 10)
                continue
            if key in (ord("q"), 27):
                return
            if key == ord("r"):
                self.message = "Refreshed."
            elif key == ord("s"):
                self.set_enabled(True)
            elif key == ord("p"):
                self.set_enabled(False)
            elif key == ord("n"):
                self.run_now()
            elif key == ord("c"):
                self.switch_coordinator()
            elif key == ord("x"):
                if self.confirm("Stop the live run now?"):
                    self.stop_live()
                else:
                    self.message = "Not stopped."
            elif key == ord("R"):
                if self.confirm("Restart: stop the live run (if any) and start a new run now?"):
                    self.stop_live()
                    time.sleep(1)
                    self.run_now()
                else:
                    self.message = "Not restarted."
            elif key in (ord("l"), curses.KEY_ENTER, 10, 13):
                self.view = "detail"
                self.detail_scroll = 0
            self.load()


def main():
    if "--once" in sys.argv:
        # Plain-text snapshot for checks and scripts: no curses.
        d = Dashboard.__new__(Dashboard)
        d.summaries = Summaries()
        d.load()
        auto = d.data.get("auto") or {}
        live = d.live_run()
        print("schedule:", "enabled" if auto.get("enabled") else "paused", auto.get("rrule"), "next", hm(kst(auto.get("nextRunAt"))))
        print("coordinator:", auto.get("agentId"))
        print("live run:", "yes, heartbeat " + hm(live[1]) if live else "no")
        for x in (d.data.get("runs") or [])[:5]:
            s = d.summaries.for_run(kst(x.get("startedAt")))
            text = ("FAILED: " + s[4]) if s and s[4] else first_line(s[1], 120) if s and s[0] else ("running" if s else "no transcript")
            print("run", x.get("runNumber"), hm(kst(x.get("startedAt"))), x.get("status"), "|", text)
        st = d.data.get("state") or {}
        for pr, r in (st.get("reviews") or {}).items():
            if r.get("status") in LIVE_REVIEW + WAITING + TRACKED:
                print("review", pr, r.get("status"), (r.get("title") or "")[:60])
        for err in d.data.get("errors") or []:
            print("error:", err)
        return 0
    curses.wrapper(lambda screen: Dashboard(screen).loop())
    return 0


if __name__ == "__main__":
    sys.exit(main())
