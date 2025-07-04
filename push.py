#!/usr/bin/env python3

"""Really simple script to push a script to AntiRaid"""
from dotenv import load_dotenv

load_dotenv()  # take environment variables

import os
import pathlib
import requests

API_URL = "https://splashtail-staging.antiraid.xyz/"
NEEDED_CAPS = ["*"] # List of needed capabilities
EVENTS = [
    "MESSAGE", 
    "INTERACTION_CREATE", 
    "KeyExpiry[builtins.remindme]", 
    "GetSettings",
    "ExecuteSetting[members]",
    "ExecuteSetting[roles]",
    "ExecuteSetting[scripts]",
] # List of events to listen to
USE_BUNDLED_TEMPLATING_TYPES = True # Use bundled types
TEMPLATE_NAME = "builtins-dev" # Name of the template
IGNORE_FILES = [
    ".env",
    ".env.sample",
    ".git",
    ".gitignore",
    ".gitmodules",
    "README.md",
    "push.py",
    "requirements.txt",
    "LICENSE",
    ".darklua.json5",
    ".venv",
    ".net"
]

contents = {}
for path in pathlib.Path(".").rglob("*"):
    ignored = False
    for f in IGNORE_FILES:
        if str(path).startswith(f):
            ignored = True
            break
    
    if ignored:
        continue

    if USE_BUNDLED_TEMPLATING_TYPES and str(path).startswith("templating-types"):
        continue # use bundled types

    print(path)

    if path.is_file():
        # Replace backslashes with forward slashes in the path string
        normalized_path = str(path).replace("\\", "/")
        with open(path, "r", errors="replace") as f:
            contents[normalized_path] = f.read()

if USE_BUNDLED_TEMPLATING_TYPES:
    NEEDED_CAPS.append("assetmanager:use_bundled_templating_types")

api_token = os.getenv("API_TOKEN")
if not api_token:
    raise ValueError("API_TOKEN is not set in the environment variables")

guild_id = os.getenv("GUILD_ID")
if not guild_id:
    raise ValueError("GUILD_ID is not set in the environment variables")

error_channel = os.getenv("ERROR_CHANNEL")
if not error_channel:
    raise ValueError("ERROR_CHANNEL is not set in the environment variables")

print("Pushing script to AntiRaid...")
res = requests.post(f"{API_URL}/guilds/{guild_id}/settings", 
    json={
        "fields": {
            "name": TEMPLATE_NAME,
            "language": "luau",
            "paused": False,
            "allowed_caps": NEEDED_CAPS,
            "events": EVENTS,
            "content": contents,
            "error_channel": error_channel,
        },
        "operation": "Create",
        "setting": "scripts"
    },
    headers={
        "Authorization": api_token,
        "Content-Type": "application/json"
    },
    timeout=180
)

message: str = None
# Handle template already exists
if res.status_code == 400:
    print("Template already exists, updating...")
    message = res.json().get("message")
    if message == "Template already exists":
        res = requests.post(f"{API_URL}/guilds/{guild_id}/settings", 
            json={
                "fields": {
                    "name": TEMPLATE_NAME,
                    "language": "luau",
                    "paused": False,
                    "allowed_caps": NEEDED_CAPS,
                    "events": EVENTS,
                    "content": contents,
                    "error_channel": error_channel,
                },
                "operation": "Update",
                "setting": "scripts"
            },
            headers={
                "Authorization": api_token,
                "Content-Type": "application/json"
            }
        )

if res.ok:
    print("Script pushed successfully")
    print(res.text)
else:
    print(f"Failed to push script with status code {res.status_code}")
    print("Response:")
    print(res.json())
    exit(1)