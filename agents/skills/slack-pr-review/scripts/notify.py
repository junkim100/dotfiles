#!/usr/bin/env python3
"""Send the user a Slack DM from a bot, so it notifies them.

Messages sent with the user's own Slack token (DMs to themselves) never notify them, so the loop posts from a bot. The PR Review Bot (assets/slack-app-manifest.json) is used when ~/.config/slack-pr-review/bot.env holds SLACK_PR_REVIEW_BOT_TOKEN and SLACK_PR_REVIEW_USER; run `notify.py --setup --user <member id>` once to write that file. Until then it falls back to the eval notifier bot named in the --env file (SLACK_EVAL_NOTIFICATOR and SLACK_EVAL_NOTIFICATOR_DM).

The message arrives on stdin as standard markdown (Slack's markdown_text). --thread-ts replies inside an earlier message's thread, in the channel --channel names (the D... id this script printed). Tokens are never printed. On success it prints {"channel", "ts", "permalink", "bot"} as JSON and exits 0; otherwise it prints the reason and exits 1, and the caller falls back to a DM it sends itself.
"""

import argparse
import getpass
import json
import os
import re
import sys
import urllib.parse
import urllib.request

API = "https://slack.com/api/"
BOT_ENV = os.path.expanduser(os.environ.get("SLACK_PR_REVIEW_BOT_ENV") or "~/.config/slack-pr-review/bot.env")


def read_env(path, names):
    values = {}
    if path and os.path.isfile(path):
        with open(path) as f:
            for line in f:
                m = re.match(r"^\s*([A-Z_]+)\s*=\s*['\"]?([^'\"\s#]+)", line)
                if m and m.group(1) in names:
                    values[m.group(1)] = m.group(2)
    return values


def call(token, method, payload, form=False):
    if form:
        data, kind = urllib.parse.urlencode(payload).encode(), "application/x-www-form-urlencoded"
    else:
        data, kind = json.dumps(payload).encode(), "application/json; charset=utf-8"
    request = urllib.request.Request(API + method, data=data, headers={"Content-Type": kind, "Authorization": "Bearer " + token})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode())


def resolve(eval_env):
    """Return (token, user, bot name): the PR Review Bot when configured, else the eval notifier."""
    names = ("SLACK_PR_REVIEW_BOT_TOKEN", "SLACK_PR_REVIEW_USER")
    own = read_env(BOT_ENV, names)
    token = os.environ.get(names[0]) or own.get(names[0])
    user = os.environ.get(names[1]) or own.get(names[1])
    if token and user:
        return token, user, "pr-review"
    names = ("SLACK_EVAL_NOTIFICATOR", "SLACK_EVAL_NOTIFICATOR_DM")
    other = read_env(eval_env, names)
    token = os.environ.get(names[0]) or other.get(names[0])
    user = os.environ.get(names[1]) or other.get(names[1])
    if token and user:
        return token, user, "eval-notifier"
    return None, None, None


def setup(user):
    token = getpass.getpass("PR Review Bot token (xoxb-...): ").strip()
    if not token.startswith("xoxb-"):
        print("setup: expected a bot token that starts with xoxb-")
        return 1
    try:
        auth = call(token, "auth.test", {}, form=True)
    except Exception as exc:
        print("setup: auth.test failed: " + type(exc).__name__)
        return 1
    if not auth.get("ok"):
        print("setup: Slack rejected the token: " + str(auth.get("error")))
        return 1
    os.makedirs(os.path.dirname(BOT_ENV), mode=0o700, exist_ok=True)
    fd = os.open(BOT_ENV, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("SLACK_PR_REVIEW_BOT_TOKEN={}\nSLACK_PR_REVIEW_USER={}\n".format(token, user))
    os.chmod(BOT_ENV, 0o600)
    sent = call(token, "chat.postMessage", {"channel": user, "markdown_text": "**PR Review Bot is set up.** Review results and questions will arrive here. Reply in a message's thread to answer it.", "unfurl_links": False})
    if not sent.get("ok"):
        print("setup: saved {}, but the test DM failed: {}".format(BOT_ENV, sent.get("error")))
        return 1
    print("setup: saved {} for bot {} in {}; test DM sent".format(BOT_ENV, auth.get("user"), auth.get("team")))
    return 0


def main():
    parser = argparse.ArgumentParser(description="Send the user a Slack DM from the PR Review Bot (or the eval notifier until it is set up); message text on stdin.")
    parser.add_argument("--env", help="the wbl-eval .env file holding the eval notifier fallback (SLACK_EVAL_NOTIFICATOR and SLACK_EVAL_NOTIFICATOR_DM)")
    parser.add_argument("--channel", help="the bot DM channel (D...) for --thread-ts; default: the user, which opens the DM")
    parser.add_argument("--thread-ts", help="reply in the thread of this message")
    parser.add_argument("--which", action="store_true", help="print which bot would send, without sending")
    parser.add_argument("--setup", action="store_true", help="store the PR Review Bot token (prompted, never echoed) and send a test DM")
    parser.add_argument("--user", help="the user's Slack member ID, for --setup")
    args = parser.parse_args()
    if args.setup:
        if not args.user:
            print("setup: pass --user <your Slack member ID>")
            return 1
        return setup(args.user)
    token, user, bot = resolve(args.env)
    if args.which:
        print(bot or "none")
        return 0 if bot else 1
    if not token:
        print("notify: no bot token configured; nothing sent")
        return 1
    text = sys.stdin.read().strip()
    if not text:
        print("notify: empty message; nothing sent")
        return 1
    payload = {"channel": args.channel or user, "markdown_text": text, "unfurl_links": False, "unfurl_media": False}
    if args.thread_ts:
        payload["thread_ts"] = args.thread_ts
    try:
        data = call(token, "chat.postMessage", payload)
    except Exception as exc:
        print("notify: request failed: " + type(exc).__name__)
        return 1
    if not data.get("ok"):
        print("notify: Slack refused the message: " + str(data.get("error")))
        return 1
    result = {"channel": data.get("channel"), "ts": data.get("ts"), "permalink": None, "bot": bot}
    try:
        link = call(token, "chat.getPermalink", {"channel": result["channel"], "message_ts": result["ts"]}, form=True)
        result["permalink"] = link.get("permalink")
    except Exception:
        pass
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
