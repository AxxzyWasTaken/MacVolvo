"""Admission refuses a reused PID and excludes foreign processes."""
import errno,json,sys,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock,patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import measure_macvolvo as capture

class Admission(unittest.TestCase):
    def test_session_ownership_and_kernel_identity(self):
        probe=Mock()
        def sample(pid,expected=0):
            if expected and pid==202:raise OSError(errno.ESTALE,'reused')
            return {'start_abstime':pid*10,'footprint_bytes':1000}
        probe.sample.side_effect=sample
        rows=[{'pid':101,'kind':'game'},{'pid':202,'kind':'game'}]
        result=SimpleNamespace(returncode=0,stdout=json.dumps({'stage':'session','processes':rows}))
        with patch.object(capture,'command',return_value='101 C:\\Games\\CS2.EXE\n202 /owned/deadlock.exe\n303 /foreign/cs2.exe\n404 /other/app\n'),patch.object(capture.subprocess,'run',return_value=result):
            found=capture.admitted_processes(Path('/worker'),Path('/root'),probe)
        self.assertEqual([row['pid'] for row in found],[101])
        self.assertEqual(found[0]['native_start_abstime'],1010)
        self.assertEqual(found[0]['name'],'cs2.exe')
        self.assertNotIn('path',found[0])

    def test_worker_failure_is_not_accepted_as_empty_success(self):
        with patch.object(capture,'command',return_value=''),patch.object(capture.subprocess,'run',return_value=SimpleNamespace(returncode=1,stdout='')):
            with self.assertRaises(RuntimeError):capture.admitted_processes(Path('/worker'),Path('/root'),Mock())
