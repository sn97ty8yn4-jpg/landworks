import importlib.util
import io
import tempfile
from pathlib import Path
import unittest

SOURCE=Path(__file__).resolve().parents[1]/'tools'/'analyse_tractor_bench.py'
spec=importlib.util.spec_from_file_location('analysis', SOURCE)
a=importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)

class ReportTest(unittest.TestCase):
    def test_no_results_not_silently_accepted(self):
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaises(FileNotFoundError):
                a.load_results(Path(td)/'notfound.csv')
    def test_incomplete_report_not_ranked(self):
        body=a.report({'BASELINE': {k:0.0 for k in a.FIELDS}})
        self.assertIn('INCOMPLETE',body)
        self.assertIn('Not run',body)
    def test_nan_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            file=Path(td)/'input.csv'
            file.write_text('engine,'+','.join(a.FIELDS)+'\nBASELINE,nan,1,1,0,0\n')
            with self.assertRaises(ValueError):
                a.load_results(file)

if __name__=='__main__':
    unittest.main()
