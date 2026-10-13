from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
STRING = r'"((?:[^"\\]|\\.)*)"'
ENTRY = re.compile(STRING + r"\s*=\s*" + STRING + r"\s*;")


def parse_table(text):
    entries = {}
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        match = ENTRY.fullmatch(line.strip())
        if not match:
            raise ValueError(f"Invalid localization entry on line {number}")
        key, value = match.groups()
        if key in entries:
            raise ValueError(f"Duplicate localization key: {key}")
        if not value:
            raise ValueError(f"Empty localization value: {key}")
        entries[key] = value
    return entries


class LocalizationTests(unittest.TestCase):
    def test_tables_cover_all_native_literal_keys(self):
        keys = set()
        pattern = re.compile(r"(?:L|NSLocalizedString)\(" + STRING)
        for source in (ROOT / "Sources/MediaForgeApp").glob("*.swift"):
            keys.update(pattern.findall(source.read_text()))
        tables = []
        for language in ("ru", "en"):
            path = ROOT / "Resources" / (language + ".lproj") / "Localizable.strings"
            table = parse_table(path.read_text())
            self.assertFalse(keys - table.keys(), f"Missing {language} keys: {keys - table.keys()}")
            tables.append(table)
        self.assertEqual(tables[0].keys(), tables[1].keys())

    def test_parser_rejects_broken_duplicate_and_empty_entries(self):
        for text in ('"key" = "value"', '"key" = "";', '"key" = "a";\n"key" = "b";'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_table(text)
        self.assertEqual(parse_table('"escaped\\"key" = "value";'), {'escaped\\"key': "value"})
