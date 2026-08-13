from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "server"
if str(SERVER) not in sys.path:
    sys.path.insert(0, str(SERVER))

from beta_identity import BetaIdentityStore


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare FIFA 14 Local FUT v2.41 BETA progression profile")
    parser.add_argument("--database", required=True)
    parser.add_argument("--reset", action="store_true")
    args = parser.parse_args()
    db = Path(args.database)
    if args.reset and db.exists():
        db.unlink()
    store = BetaIdentityStore(str(db), "existing")
    summary = store.beta_profile_summary()
    payload = {
        "profileKind": store.profile_kind(),
        "route": "retail-returning-user",
        "hasClub": store.has_club(),
        "snapshot": store.snapshot(),
        "beta": summary,
    }
    print(json.dumps(payload, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
