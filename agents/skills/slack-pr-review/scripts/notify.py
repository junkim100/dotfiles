#!/usr/bin/env python3
"""Send the user a Slack DM from a bot, so it notifies them.

Messages sent with the user's own Slack token (DMs to themselves) never notify them. This posts the message on stdin (standard markdown, Slack's markdown_text) from the eval notifier bot instead: token SLACK_EVAL_NOTIFICATOR (xoxb with chat:write and im:write) and target SLACK_EVAL_NOTIFICATOR_DM (the user's member ID), read from the environment or from the .env file given with --env. --thread-ts replies inside an earlier message's thread, in the channel --channel names (the bot DM's D... id this script printed). The token is never printed. On success it prints {"channel", "ts", "permalink"} as JSON and exits 0; otherwise it prints the reason and exits 1, and the caller falls back to a DM it sends itself.
"""

import argparse
import json
import os
import re
import sys
import urllib.parse
import urllib.request

API = "https://slack.com/api/"


def read_env(path):
    values = {}
    if path and os.path.isfile(path):
        with open(path) as f:
            for line in f:
                m = re.match(r"^\s*(SLACK_EVAL_NOTIFICATOR(?:_DM)?)\s*=\s*['\"]?([^'\"\s#]+)", line)
                if m:
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


def main():
    parser = argparse.ArgumentParser(description="Send the user a Slack DM from the eval notifier bot; message text on stdin.")
    parser.add_argument("--env", help="a .env file holding SLACK_EVAL_NOTIFICATOR and SLACK_EVAL_NOTIFICATOR_DM")
    parser.add_argument("--channel", help="the bot DM channel (D...) for --thread-ts; default: the user ID, which opens the DM")
    parser.add_argument("--thread-ts", help="reply in the thread of this message")
    args = parser.parse_args()
    values = read_env(args.env)
    token = os.environ.get("SLACK_EVAL_NOTIFICATOR") or values.get("SLACK_EVAL_NOTIFICATOR")
    target = args.channel or os.environ.get("SLACK_EVAL_NOTIFICATOR_DM") or values.get("SLACK_EVAL_NOTIFICATOR_DM")
    if not (token and target):
        print("notify: SLACK_EVAL_NOTIFICATOR or SLACK_EVAL_NOTIFICATOR_DM is not set; nothing sent")
        return 1
    text = sys.stdin.read().strip()
    if not text:
        print("notify: empty message; nothing sent")
        return 1
    payload = {"channel": target, "markdown_text": text, "unfurl_links": False, "unfurl_media": False}
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
    result = {"channel": data.get("channel"), "ts": data.get("ts"), "permalink": None}
    try:
        link = call(token, "chat.getPermalink", {"channel": result["channel"], "message_ts": result["ts"]}, form=True)
        result["permalink"] = link.get("permalink")
    except Exception:
        pass
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
