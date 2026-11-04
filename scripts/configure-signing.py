#!/usr/bin/env python3
"""Save non-secret signing identifiers without modifying the generated project."""
import argparse
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--team-id", required=True, help="10-character Apple developer team ID")
parser.add_argument("--bundle-id", required=True, help="Explicit App ID registered with MusicKit enabled")
args = parser.parse_args()
if not re.fullmatch(r"[A-Z0-9]{10}", args.team_id):
    parser.error("team ID must contain 10 uppercase letters or digits")
if (not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id)
        or args.bundle_id.startswith("com.example.") or "yourname" in args.bundle_id):
    parser.error("use your registered reverse-domain bundle ID, without wildcards or placeholders")

root = Path(__file__).resolve().parent.parent
config = root / "Config" / "Local.xcconfig"
config.write_text(
    "// Local signing identifiers. Ignored by git. No passwords or keys.\n"
    f"DEVELOPMENT_TEAM = {args.team_id}\n"
    f"PRODUCT_BUNDLE_IDENTIFIER = {args.bundle_id}\n"
    "CODE_SIGN_IDENTITY = Apple Development\n"
)
print("Saved Config/Local.xcconfig. Run the StillPlayer scheme in Xcode.")
print("MusicKit must be enabled for this exact App ID in the developer portal.")
