"""Обновить DOCX из MD, сохранив персональный титульный лист каждого DOCX.

Запуск: python -X utf8 tools/refresh_docx_from_md.py.
XML титульного листа и остальные части ZIP-пакета сохраняются без пересериализации.
"""
from pathlib import Path
import re
from xml.sax.saxutils import escape
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
NS = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
W = '{' + NS['w'] + '}'


def blocks(text):
    # MD может содержать шаблонный титул: он не заменяет заполненный титул Word.
    start = re.search(r'(?m)^#{1,6}\s+1\.\s+Задание\s*$', text)
    if not start:
        raise ValueError('Не найден раздел 1. Задание')
    pending = []
    code = False
    for line in text[start.start():].splitlines():
        heading = re.match(r'^(#{1,6})\s+(.+)$', line)
        special = line.startswith('```') or heading or not line.strip() or line.startswith('- ')
        if not code and special and pending:
            yield 'Normal', ' '.join(pending)
            pending = []
        if line.startswith('```'):
            code = not code
        elif code:
            yield 'Code', line
        elif heading:
            yield 'Heading1' if len(heading[1]) == 1 else 'Heading2', heading[2]
        elif line.startswith('- '):
            yield 'Normal', line
        elif line.strip():
            pending.append(line.strip())
    if code:
        raise ValueError('Не закрыт блок кода')
    if pending:
        yield 'Normal', ' '.join(pending)


def refresh(path):
    source = path.with_suffix('.md')
    expected = list(blocks(source.read_text(encoding='utf-8-sig')))
    with ZipFile(path) as archive:
        infos = archive.infolist()
        package = {i.filename: archive.read(i.filename) for i in infos}
    original = package['word/document.xml'].decode('utf-8')
    document = ET.fromstring(original)
    body = document.find('w:body', NS)
    boundary = next(i for i, p in enumerate(body)
                    if ''.join(t.text or '' for t in p.findall('.//w:t', NS)).strip() == '1. Задание')
    # Находим исходный абзац первого раздела, не трогая предшествующие таблицы,
    # рисунки, разрывы страниц, поля и пространства имён титульной страницы.
    matches = list(re.finditer(r'<w:p(?:\s[^>]*)?>.*?</w:p>', original, re.S))
    first = next(m for m in matches if '1. Задание' in m.group())
    prefix = original[:first.start()]
    section_start = original.rfind('<w:sectPr')
    assert section_start > first.end()
    suffix = original[section_start:]
    styles_xml = package['word/styles.xml'].decode('utf-8')
    styles = ET.fromstring(styles_xml)
    names = {s.find('w:name', NS).get(W+'val').lower(): s.get(W+'styleId')
             for s in styles.findall('w:style', NS) if s.find('w:name', NS) is not None}
    normal = next(s.get(W+'styleId') for s in styles.findall('w:style', NS)
                  if s.get(W+'type') == 'paragraph' and s.get(W+'default') == '1')
    mapping = {'Normal': normal, 'Heading1': names['heading 1'],
               'Heading2': names['heading 2'], 'Code': names['code']}
    rendered = []
    for style, text in expected:
        props = f'<w:pStyle w:val="{mapping[style]}"/>'
        if text.startswith('[Место для изображения:'):
            props += '<w:spacing w:before="120" w:after="2400"/><w:keepNext/>'
        run_props = '<w:rPr><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr>' if style == 'Code' else ''
        rendered.append(f'<w:p><w:pPr>{props}</w:pPr><w:r>{run_props}<w:t xml:space="preserve">{escape(text)}</w:t></w:r></w:p>')
    updated = prefix + ''.join(rendered) + suffix
    # На титуле уже имеется явный разрыв страницы; второй pageBreakBefore не нужен.
    package['word/document.xml'] = updated.encode('utf-8')
    code_pattern = r'<w:style\b[^>]*w:styleId="' + re.escape(mapping['Code']) + r'"[^>]*>.*?</w:style>'
    match = re.search(code_pattern, styles_xml, re.S)
    assert match
    code_style = match.group()
    for size in ['sz', 'szCs']:
        pat = rf'<w:{size}\b[^>]*/>'
        new = f'<w:{size} w:val="20"/>'
        if re.search(pat, code_style):
            code_style = re.sub(pat, new, code_style)
        else:
            code_style = code_style.replace('</w:rPr>', new + '</w:rPr>')
    package['word/styles.xml'] = (styles_xml[:match.start()] + code_style + styles_xml[match.end():]).encode('utf-8')
    temp = path.with_suffix('.refresh.docx')
    with ZipFile(temp, 'w') as archive:
        for info in infos:
            archive.writestr(info, package[info.filename])
    with ZipFile(temp) as archive:
        assert archive.testzip() is None
        output = archive.read('word/document.xml').decode('utf-8')
        assert output.startswith(prefix) and output.endswith(suffix)
        result = ET.fromstring(output).find('w:body', NS)
        assert [ET.tostring(p) for p in result[:boundary]] == [ET.tostring(p) for p in body[:boundary]]
        actual = [(p.find('w:pPr/w:pStyle', NS).get(W+'val'),
                   ''.join(t.text or '' for t in p.findall('.//w:t', NS))) for p in result[boundary:-1]]
        assert actual == [(mapping[s], t) for s, t in expected]
        for p in result[boundary:-1]:
            if p.find('w:pPr/w:pStyle', NS).get(W+'val') == mapping['Code']:
                assert p.find('w:r/w:rPr/w:sz', NS).get(W+'val') == '20'
    temp.replace(path)
    print(f'OK {path.relative_to(ROOT)}: {len(expected)} paragraphs; title preserved; code 10 pt')


if __name__ == '__main__':
    for folder in [ROOT / 'reports', ROOT / 'kirik/reports']:
        for path in sorted(folder.glob('*.docx')):
            if path.with_suffix('.md').exists():
                refresh(path)
