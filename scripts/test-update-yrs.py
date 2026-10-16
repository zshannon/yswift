import difflib
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('update_yrs', Path(__file__).with_name('update-yrs.py'))
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class VendorMergeTests(unittest.TestCase):
    def exercise(self, base, ours, theirs):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            current, incoming = root / 'current', root / 'incoming'
            for path in (current, incoming):
                (path / 'src').mkdir(parents=True)
            (current / 'src/undo.rs').write_text(ours)
            if theirs is not None:
                (incoming / 'src/undo.rs').write_text(theirs)
            patch = root / 'fix.patch'
            patch.write_text(''.join(difflib.unified_diff(base.splitlines(True), ours.splitlines(True),
                                                        fromfile='a/src/undo.rs', tofile='b/src/undo.rs')))
            conflicts = updater.rebase_patch(current, incoming, patch)
            return conflicts, (incoming / 'src/undo.rs').read_text(), patch.read_text()

    def test_preserves_independent_upstream_and_local_changes(self):
        base = '\n'.join(str(n) for n in range(20)) + '\n'
        ours = base.replace('18\n', 'local fix\n')
        theirs = base.replace('1\n', 'upstream\n', 1)
        conflicts, result, patch = self.exercise(base, ours, theirs)
        self.assertEqual(conflicts, [])
        self.assertEqual(result, theirs.replace('18\n', 'local fix\n'))
        self.assertIn('+local fix', patch)
        self.assertNotIn('+upstream', patch)

    def test_already_upstream_fix_removes_local_patch(self):
        conflicts, result, patch = self.exercise('old\n', 'fixed\n', 'fixed\n')
        self.assertEqual((conflicts, result, patch), ([], 'fixed\n', ''))

    def test_conflict_keeps_both_sides_and_blocks_compilation(self):
        conflicts, result, _ = self.exercise('old\n', 'local fix\n', 'upstream fix\n')
        self.assertEqual(conflicts, ['src/undo.rs'])
        self.assertIn('<<<<<<< YSwift fix', result)
        self.assertIn('local fix', result)
        self.assertIn('upstream fix', result)

    def test_upstream_deletion_does_not_silently_drop_local_fix(self):
        conflicts, result, _ = self.exercise('old\n', 'local fix\n', None)
        self.assertEqual(conflicts, ['src/undo.rs'])
        self.assertIn('<<<<<<<', result)
        self.assertIn('local fix', result)


if __name__ == '__main__':
    unittest.main()
