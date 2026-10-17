import difflib
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('update_yrs', Path(__file__).with_name('update-yrs.py'))
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class ReleaseSelectionTests(unittest.TestCase):
    def test_selects_numeric_stable_release_and_excludes_prereleases_and_yanked_versions(self):
        entries = [{'vers': version, 'yanked': yanked} for version, yanked in [
            ('0.9.0', False), ('0.28.0', False), ('0.29.0-rc.1', False), ('0.30.0', True),
        ]]
        self.assertEqual(updater.latest_release(entries)['vers'], '0.28.0')

    def test_same_published_version_and_checksum_is_not_an_update(self):
        previous = {'version': '0.28.0', 'archive_sha256': 'published', 'revision': 'older-main'}
        self.assertFalse(updater.needs_update(previous, {'vers': '0.28.0', 'cksum': 'published'}))

    def test_new_release_is_an_update_but_older_release_is_not(self):
        previous = {'version': '0.28.0', 'archive_sha256': 'published'}
        self.assertTrue(updater.needs_update(previous, {'vers': '0.29.0', 'cksum': 'new'}))
        self.assertFalse(updater.needs_update(previous, {'vers': '0.27.2', 'cksum': 'old'}))

    def test_unreleased_archive_is_replaced_with_published_version(self):
        previous = {'version': '0.28.0', 'archive_sha256': 'built-from-main'}
        self.assertTrue(updater.needs_update(previous, {'vers': '0.28.0', 'cksum': 'published'}))


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
