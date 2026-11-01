#!/usr/bin/env python3
"""Regression controls for the enum-layout rebuild guard."""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('enum_stamp', Path(__file__).with_name('enum-layout-stamp.py'))
stamp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stamp)


class EnumLayoutStampTests(unittest.TestCase):
    def digest(self, source):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Example.swift').write_text(source, encoding='utf-8')
            return stamp.stamp(root)[0]

    def test_multiline_associated_value_type_changes_layout(self):
        source = 'enum State {\n case payload(\n  value: Int\n )\n}'
        self.assertNotEqual(self.digest(source), self.digest(source.replace('Int', 'String')))

    def test_cases_remain_owned_by_their_distinct_enum(self):
        source = 'enum A { enum State { case a; case b } }; enum B { enum State { case c } }'
        moved = 'enum A { enum State { case a } }; enum B { enum State { case b; case c } }'
        self.assertNotEqual(self.digest(source), self.digest(moved))

    def test_continued_case_list_includes_the_following_line(self):
        source = 'enum State {\n case a,\n b\n}'
        self.assertNotEqual(self.digest(source), self.digest(source.replace(' b', ' c')))

    def test_comment_and_switch_edits_keep_layout(self):
        source = 'enum State {\n case a\n func x() { switch self { case .a: break } }\n}'
        self.assertEqual(self.digest(source), self.digest(source.replace('break', 'return')))
        self.assertEqual(self.digest(source), self.digest(source + '\n// case b\n'))

    def test_failed_cleanup_cannot_replace_the_old_stamp(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            record = app / '.build/enum-layout.stamp'
            record.parent.mkdir()
            record.write_text('previous\n')
            def refused_cleanup(path, ignore_errors=False):
                if not ignore_errors:
                    raise PermissionError('fixture')

            with patch.object(stamp.sys, 'argv', ['stamp', directory]), \
                 patch.object(stamp.shutil, 'rmtree', side_effect=refused_cleanup), \
                 contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(PermissionError):
                    stamp.main()
            self.assertEqual(record.read_text(), 'previous\n')

    def test_missing_stamp_cleans_preexisting_objects_once(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            build = app / '.build'
            build.mkdir()
            stale = build / 'stale.o'
            stale.write_bytes(b'old object')
            with patch.object(stamp.sys, 'argv', ['stamp', directory]), \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(stamp.main(), 0)
                self.assertFalse(stale.exists())
                stable = build / 'new.o'
                stable.write_bytes(b'new object')
                self.assertEqual(stamp.main(), 0)
                self.assertTrue(stable.exists())


if __name__ == '__main__':
    unittest.main()
