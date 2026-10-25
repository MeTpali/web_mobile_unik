"""Три лабораторные по заданию 2026 года: MD/DOCX с единым оформлением."""
import ast
import importlib.util
import json
import re
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'reports'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
ET.register_namespace('w', W)
ET.register_namespace('r', R)
def tag(s): return '{' + W + '}' + s


def module(lab):
    spec = importlib.util.spec_from_file_location(lab + '_report', ROOT / lab / 'tools/build_report.py')
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


_spec = importlib.util.spec_from_file_location('comments_helper', ROOT / 'tools/comments_helper.py')
HELPERS = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(HELPERS)


def python_code(text):
    # Удаление единственного docstring оставило бы пустой класс/функцию.
    # В листинге заменяем такой docstring на эквивалентный pass.
    lines = text.splitlines(keepends=True)
    offsets = [0]
    for line in lines: offsets.append(offsets[-1] + len(line))
    replacements = []
    for node in ast.walk(ast.parse(text)):
        if isinstance(node, (ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)) and len(node.body) == 1:
            first = node.body[0]
            if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
                start = offsets[first.lineno - 1] + len(lines[first.lineno - 1].encode()[:first.col_offset].decode())
                end = offsets[first.end_lineno - 1] + len(lines[first.end_lineno - 1].encode()[:first.end_col_offset].decode())
                replacements.append((start, end))
    for start, end in sorted(replacements, reverse=True): text = text[:start] + 'pass' + text[end:]
    return HELPERS.remove_python_comments(text)


def hash_code(text):
    output = []
    for line in text.splitlines():
        if line.lstrip().startswith('%dnl'): continue
        quote, escaped, kept = None, False, []
        for char in line:
            if escaped:
                kept.append(char); escaped = False; continue
            if char == '\\':
                kept.append(char); escaped = True; continue
            if quote:
                if char == quote: quote = None
            elif char in ('"', "'"): quote = char
            elif char == '#' and (not kept or kept[-1].isspace()): break
            kept.append(char)
        output.append(''.join(kept))
    return '\n'.join(output)


def listing(path):
    text = (ROOT / path).read_text()
    suffix = Path(path).suffix
    if suffix == '.py': text = python_code(text)
    elif suffix in ('.yaml', '.yml', '.spec', '.desktop', '.sh', '.conf', '.service', '.pro') or path.endswith('CMakeLists.txt'):
        text = hash_code(text)
    else:
        # JSX-комментарий включает фигурные скобки контейнера.
        if suffix == '.jsx': text = re.sub(r'\{\s*/\*.*?\*/\s*\}', '', text, flags=re.S)
        text = HELPERS.remove_c_comments(text)
    return re.sub(r'\n{3,}', '\n\n', '\n'.join(s.rstrip() for s in text.splitlines())).strip()


def title(number, name, variant):
    return '\n\n'.join([
        '[Наименование образовательной организации]', '[Факультет / кафедра]',
        '', '', 'ОТЧЁТ', f'по лабораторной работе № {number}', 'по дисциплине',
        '«Разработка мобильных и web-приложений»', name, 'Вариант № 1 — ' + variant,
        '', '', 'Выполнил: [ФИО студента]', 'Группа: [номер группы]',
        'Проверил: [ФИО преподавателя]', '', '', '[Город] — 2026', '', '---'])


def task(number):
    text = (ROOT / 'Задания_по_курсу_Разработка_мобильных_и_web_2026.md').read_text()
    text = text.split(f'**Лабораторная работа №{number}.', 1)[1].split('**', 1)[1]
    text = text.split('Варианты заданий', 1)[0].strip().replace('**', '')
    text = re.sub(r'(?m)^Часть\s+\d+\.?\s*', '', text)
    return text


def sources(files):
    result = []
    for index, (path, description) in enumerate(files, 1):
        result.append(f'## 2.3.{index}. {path}\n\n{description}\n\n```\n{listing(path)}\n```')
    return '\n\n'.join(result)


def docx(path, markdown, template):
    root = ET.Element(tag('document'))
    body = ET.SubElement(root, tag('body'))
    title_page, content = markdown.split('\n\n---\n\n', 1)

    def paragraph(text, style='Normal', page_break=False):
        p = ET.SubElement(body, tag('p'))
        props = ET.SubElement(p, tag('pPr'))
        ET.SubElement(props, tag('pStyle'), {tag('val'): style})
        if page_break: ET.SubElement(props, tag('pageBreakBefore'))
        if text:
            run = ET.SubElement(p, tag('r'))
            ET.SubElement(run, tag('t'), {'{http://www.w3.org/XML/1998/namespace}space': 'preserve'}).text = text

    for line in title_page.split('\n\n'):
        if not line: paragraph(''); continue
        style = 'TitleSmall'
        if line == 'ОТЧЁТ': style = 'Title'
        elif line.startswith(('Выполнил:', 'Группа:', 'Проверил:')): style = 'Signature'
        paragraph(line, style)
    code, text = False, []
    def flush():
        if text:
            paragraph(' '.join(text)); text.clear()
    first = True
    for line in content.splitlines():
        if line.startswith('```'):
            flush(); code = not code; continue
        if code: paragraph(line, 'Code'); continue
        if line.startswith('# '):
            flush(); paragraph(line[2:], 'Heading1', first); first = False
        elif line.startswith('## '):
            flush(); paragraph(line[3:], 'Heading2')
        elif not line.strip(): flush()
        else: text.append(line)
    flush()
    # Оформление, поля A4, стили и footer взяты из существующих reports.
    section = ET.SubElement(body, tag('sectPr'))
    ET.SubElement(section, tag('footerReference'), {tag('type'): 'default', '{' + R + '}id': 'rIdFooter'})
    ET.SubElement(section, tag('pgSz'), {tag('w'): '11906', tag('h'): '16838'})
    ET.SubElement(section, tag('pgMar'), {tag('top'): '1134', tag('bottom'): '1134', tag('left'): '1701', tag('right'): '850', tag('header'): '567', tag('footer'): '567', tag('gutter'): '0'})
    ET.SubElement(section, tag('titlePg'))
    with ZipFile(path, 'w', ZIP_DEFLATED) as archive:
        for name, data in template.items():
            if name == 'word/document.xml': data = ET.tostring(root, encoding='utf-8', xml_declaration=True)
            archive.writestr(name, data)

