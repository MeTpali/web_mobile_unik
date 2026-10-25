"""Единый генератор выпускает по одному отчёту MD/DOCX для каждой лабораторной."""
from pathlib import Path
import runpy
import sys
if __name__ == '__main__':
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
    runpy.run_path(str(Path(__file__).resolve().parents[2] / 'tools/build_reports.py'), run_name='__main__')
