from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATABASE = ROOT / "apps/lexpdf_app/lib/src/core/storage/local_database.dart"

text = DATABASE.read_text(encoding="utf-8")
pattern = re.compile(
    r"\n  \}\n\n\n(    if \(version < 10\) \{.*?\n    \})\n\n  void close\(\) => database\.dispose\(\);",
    re.S,
)
replacement = r"\n\n\1\n  }\n\n  void close() => database.dispose();"
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise RuntimeError(
        f"schema v10 migration relocation: expected exactly one match, got {count}"
    )
DATABASE.write_text(text, encoding="utf-8")
print("Schema v10 migration moved inside _migrate().")
