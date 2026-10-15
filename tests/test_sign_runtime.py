"""Archive validation must fail before signing a tampered runtime."""
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from sign_runtime import extract_verified


class RuntimeSigningTests(unittest.TestCase):
    def archive(self, root, content=b'payload', name='bin/tool', duplicate=False):
        path = root / 'input.tar.gz'
        manifest = {'version': 'test', 'files': {name: {
            'sha256': hashlib.sha256(b'payload').hexdigest(), 'bytes': 7}}}
        with tarfile.open(path, 'w:gz') as tar:
            for key, data in [('runtime.json', json.dumps(manifest).encode()), (name, content)] + ([(name, content)] if duplicate else []):
                item = tarfile.TarInfo(key)
                item.size = len(data)
                tar.addfile(item, io.BytesIO(data))
        return path

    def test_valid_payload(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            result = extract_verified(self.archive(root), root / 'out')
            self.assertEqual(result['version'], 'test')
            self.assertEqual((root / 'out/bin/tool').read_bytes(), b'payload')

    def test_tampered_payload(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            with self.assertRaisesRegex(ValueError, 'Manifest mismatch'):
                extract_verified(self.archive(root, content=b'changed'), root / 'out')

    def test_duplicate(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            with self.assertRaisesRegex(ValueError, 'Duplicate'):
                extract_verified(self.archive(root, duplicate=True), root / 'out')

    def test_escape(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            with self.assertRaisesRegex(ValueError, 'Unsafe archive path'):
                extract_verified(self.archive(root, name='../escape'), root / 'out')
            self.assertFalse((root / 'escape').exists())


if __name__ == '__main__':
    unittest.main()
