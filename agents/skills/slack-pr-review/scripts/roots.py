#!/usr/bin/env python3
"""Keep each PR thread's root in the bot DM showing the PR's state as one reaction.

The state follows from the review's status and the PR's GitHub state, in this order: :loading: while a review or fix check is queued or running; :merged: once the PR is merged; :x: when the latest review or fix check failed; :heavy_minus_sign: when the loop decided not to review the PR; no reaction otherwise (the review waits for the user's reply, the author's fixes are being watched, the PR is approved but not merged yet, or it was closed without merging). :done: is never a root state: it marks the user's own replies whose request was carried out.

`roots.py` syncs every review that has a thread; `roots.py owner/repo#N ...` syncs only those; `--dry-run` prints the changes without making them. It reads the roots' current reactions from the DM history, changes only the bot's own reactions, records the PR's GitHub state on the review (`pr_state`), and prints one line per root it changed. Runs on the macOS system Python (3.9).
"""

import argparse
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import notify  # noqa: E402  # pyright: ignore[reportMissingImports]
import state  # noqa: E402  # pyright: ignore[reportMissingImports]

# Every emoji a root may carry as its state; :done: was the finished state before :merged:, so it is removed where found.
ROOT_EMOJIS = ("loading", "merged", "x", "heavy_minus_sign", "done")


def github_state(pr):
    """OPEN, MERGED, or CLOSED from gh, or None when gh cannot tell."""
    repo, number = pr.split("#")
    try:
        out = subprocess.run(["gh", "pr", "view", number, "--repo", repo, "--json", "state"], capture_output=True, text=True, timeout=30)
        return json.loads(out.stdout).get("state") if out.returncode == 0 else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def wanted(record, pr_state):
    status = record.get("status")
    if status in state.REVIEW_ACTIVE:
        return "loading"
    if pr_state == "MERGED":
        return "merged"
    if status == "failed":
        return "x"
    if status == "skipped":
        return "heavy_minus_sign"
    return None


def root_reactions(token, channel, stamps):
    """{root ts: set of emoji names the bot put on it} for the given top-level messages of one DM."""
    found = {}
    cursor = None
    while True:
        params = {"channel": channel, "oldest": min(stamps), "latest": max(stamps), "inclusive": "true", "limit": 200}
        if cursor:
            params["cursor"] = cursor
        data = notify.call(token, "conversations.history", params, form=True)
        if not data.get("ok"):
            raise RuntimeError("conversations.history refused: " + str(data.get("error")))
        for message in data.get("messages", []):
            if message.get("ts") in stamps:
                found[message["ts"]] = message.get("reactions") or []
        cursor = (data.get("response_metadata") or {}).get("next_cursor")
        if not cursor:
            return found


def main():
    parser = argparse.ArgumentParser(description="Set the state reaction on PR thread roots in the bot DM from each review's status and the PR's GitHub state.")
    parser.add_argument("prs", nargs="*", help="owner/repo#N reviews to sync (default: every review with a thread)")
    parser.add_argument("--dry-run", action="store_true", help="print what would change without changing it")
    args = parser.parse_args()
    token, _, bot = notify.resolve(None)
    if bot != "pr-review":
        print("roots: the PR Review Bot is not set up; nothing changed")
        return 1
    me = notify.call(token, "auth.test", {}, form=True).get("user_id")
    data = state.load()
    targets = {}
    for pr, record in data["reviews"].items():
        thread = record.get("thread") or {}
        if thread.get("channel") and thread.get("ts") and (not args.prs or pr in args.prs):
            targets[pr] = record
    missing = [pr for pr in args.prs if pr not in targets]
    for pr in missing:
        print("roots: {} has no thread; skipped".format(pr))
    pr_states = {}
    for pr, record in targets.items():
        known = record.get("pr_state")
        if record.get("status") in state.REVIEW_ACTIVE or known == "MERGED":
            pr_states[pr] = known
        else:
            pr_states[pr] = github_state(pr) or known
    by_channel = {}
    for pr, record in targets.items():
        by_channel.setdefault(record["thread"]["channel"], []).append(pr)
    changed, failed = [], []
    for channel, prs in by_channel.items():
        stamps = {targets[pr]["thread"]["ts"] for pr in prs}
        try:
            current = root_reactions(token, channel, stamps)
        except Exception as exc:
            print("roots: could not read the DM: {}".format(exc))
            return 1
        for pr in prs:
            ts = targets[pr]["thread"]["ts"]
            if ts not in current:
                print("roots: #{} root {} not found in the DM; skipped".format(pr.split("#")[-1], ts))
                continue
            mine = {r["name"] for r in current[ts] if me in (r.get("users") or []) and r.get("name") in ROOT_EMOJIS}
            want = wanted(targets[pr], pr_states[pr])
            steps = [("reactions.remove", name) for name in sorted(mine - {want})]
            if want and want not in mine:
                steps.append(("reactions.add", want))
            if not steps:
                continue
            line = "#{}: {} ({})".format(pr.split("#")[-1], " ".join(("-" if m.endswith("remove") else "+") + n for m, n in steps), targets[pr].get("status"))
            if args.dry_run:
                print("would change " + line)
                changed.append(pr)
                continue
            ok = True
            for method, name in steps:
                result = notify.call(token, method, {"channel": channel, "timestamp": ts, "name": name}, form=True)
                if not result.get("ok") and result.get("error") not in ("no_reaction", "already_reacted"):
                    print("roots: #{} {} {} refused: {}".format(pr.split("#")[-1], method, name, result.get("error")))
                    ok = False
            (changed if ok else failed).append(pr)
            if ok:
                print(line)
    if not args.dry_run:
        with state.locked() as live:
            for pr, value in pr_states.items():
                if value and pr in live["reviews"]:
                    live["reviews"][pr]["pr_state"] = value
    if not changed and not failed:
        print("roots: nothing to change")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
