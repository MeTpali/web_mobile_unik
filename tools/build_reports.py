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


HELPERS = module('lab2')


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
        '«Разработка мобильных и web-приложений»', name, 'Вариант № 6 — ' + variant,
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


def generate():
    metadata = json.loads((ROOT / 'tools/report_sources.json').read_text())
    m2, m3 = module('lab2'), module('lab3')
    with ZipFile(ROOT / 'tools/report_template.docx') as archive:
        template = {name: archive.read(name) for name in archive.namelist()}
    names = [
        'Взаимодействие с web-клиентом и WebSockets в мобильном приложении Aurora OS',
        'REST API, HTTPS и offline-клиент на Aurora OS',
        'Сборка, подпись, деплой и масштабирование приложений Aurora OS',
    ]
    for number in (1, 2, 3):
        variant = 'Генератор случайных чисел' if number == 1 else 'Расходы'
        text = title(number, names[number - 1], variant) + '\n\n# 1. Задание\n\n' + task(number)
        text += '\n\n' + ('Генератор случайных целых чисел в заданном пользователем диапазоне.' if number == 1 else 'Учёт расходов с полями: дата, категория, сумма и комментарий; CRUD, offline-режим и синхронизация.')
        text += '\n\n# 2. Выполнение\n\n## 2.1. Средства разработки и структура решения\n\n'
        if number == 1:
            files = metadata['lab1']
            text += 'Реализован генератор случайных чисел с браузерным и мобильным интерфейсами. Браузерный интерфейс использует React и Vite, HTTP API — Node.js и Express. Приложение Flutter для Авроры обращается к Python-серверу FastAPI через постоянное WebSocket-соединение. Проекты находятся в lab1/lab-01 и lab1/lab-02 и вместе составляют одну лабораторную работу.\n\n'
            text += '## 2.2. Взаимодействие компонентов\n\nБраузер отправляет асинхронный POST /api/random по относительному адресу; Express раздаёт собранный интерфейс и API с порта 3000. CSS содержит адаптивные правила @media. Flutter-клиент задаёт адрес ws://<IP-ПК>:8000/ws/random, передаёт границы в JSON, сопоставляет ответы по request_id и показывает результат и историю. UI, контроллер, модели и WebSocket-сервис разделены.\n\n'
            text += 'Обе границы включены; допустимы целые числа от −1 000 000 000 до 1 000 000 000. Проверяются порядок границ, формат ввода и ошибки сети; ожидание ответа ограничено тайм-аутом.\n\n'
            validation = '\n\n'.join(metadata['lab1_validation'])
            validation = validation.replace('~/Unik/web_mobile_unik/lab-01', '~/Unik/web_mobile_unik/lab1/lab-01').replace('~/Unik/web_mobile_unik/lab-02', '~/Unik/web_mobile_unik/lab1/lab-02')
        else:
            lab = f'lab{number}'
            mod = m2 if number == 2 else m3
            files = [(lab + '/' + path, description) for path, description in mod.FILES]
            old = (ROOT / lab / 'docs/REPORT.md').read_text()
            intro = old.split('## 2. Выполнение\n\n', 1)[1].split('## 2.1.', 1)[0].strip()
            text += intro + '\n\n## 2.2. Взаимодействие компонентов\n\n'
            if number == 2:
                text += 'FastAPI предоставляет версионированный REST API /api/v1/ по HTTPS. JWT сохраняется клиентом в QSettings. Асинхронный транспорт QNetworkAccessManager передаёт JSON; QtSql хранит расходы и очередь offline-операций. Для повторов используются Idempotency-Key, для конфликтов — версии записей. ETag, Cache-Control и Last-Modified обеспечивают проверку актуальности кэша. Вспомогательная HTML-страница позволяет выполнить полный CRUD в браузере.\n\n'
            else:
                text += 'nginx принимает HTTPS/WSS на порту 9443 и распределяет запросы между двумя systemd-инстансами. Backend используют общую PostgreSQL и JWT-ключ. PostgreSQL LISTEN/NOTIFY передаёт события между процессами; WSS уведомляет телефон, который перечитывает REST-снимок. Blue-green выполняется с проверкой готовности новой группы, reload nginx и возможностью отката.\n\n'
            validation = old.split('## 2.2. Проверка\n\n', 1)[1].strip()
            if number == 2:
                validation += '\n\nКоманды запуска:\n\n```bash\ncd ~/Unik/web_mobile_unik/lab2/backend\n.venv/bin/python run.py\n```\n\nНа телефоне открыть приложение «Расходы · ЛР2» и указать https://<IP-ПК>:8443. Учебный вход: demo / demo12345.'
            else:
                validation += '\n\nКоманды переключения версий:\n\n```bash\ncd ~/Unik/web_mobile_unik/lab3\nsudo bash deploy/scripts/switch-release.sh green\nsudo bash deploy/scripts/switch-release.sh blue\n```\n\nЕдиный адрес браузера и приложения: https://<IP-ПК>:9443. Учебный вход: demo / demo12345.'
        text += sources(files) + '\n\n## 2.4. Запуск и проверка\n\n' + validation.strip() + '\n'
        # Ссылки и технические пути приводим к действующей структуре репозитория.
        text = re.sub(r'(?m)^Часть\s+\d+\.?\s*', '', text)
        base = OUT / f'Отчёт_ЛР_{number:02}'
        base.with_suffix('.md').write_text(text)
        docx(base.with_suffix('.docx'), text, template)
        print(f'ЛР {number}: {len(files)} основных файлов, MD + DOCX')


if __name__ == '__main__': generate()
