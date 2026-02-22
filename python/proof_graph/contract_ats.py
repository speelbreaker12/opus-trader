"""Extract AT IDs from CONTRACT.md."""
import re
from pathlib import Path

AT_ID_RE = re.compile(r'\bAT-\d+\b')


def extract_contract_ats(contract_path: Path) -> set[str]:
    """Return set of full AT ID strings (e.g. {"AT-201", "AT-920"}) from CONTRACT.md."""
    text = contract_path.read_text(encoding="utf-8")
    return set(AT_ID_RE.findall(text))
