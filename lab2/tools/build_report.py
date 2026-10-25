"""Создаёт Markdown и DOCX: исходники остаются с комментариями, листинги — без них."""
import ast
import io
import re
import tokenize
from pathlib import Path
from xml.etree.ElementTree import Element, SubElement, tostring
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    ('backend/app/schemas.py', 'Схемы JSON и правила валидации.'),
    ('backend/app/storage.py', 'Таблицы SQLite, транзакции и хеширование паролей.'),
    ('backend/app/main.py', 'REST API v1, JWT, права доступа, версии, кэширование и повторы операций.'),
    ('backend/run.py', 'Запуск HTTPS-сервера Uvicorn.'),
    ('backend/static/index.html', 'Адаптивная вспомогательная браузерная форма.'),
    ('backend/static/browser.js', 'Вход и браузерный CRUD через XMLHttpRequest.'),
    ('client/src/main.cpp', 'Точка входа нативного приложения и создание зависимостей.'),
    ('client/src/apiclient.h', 'Интерфейс HTTP-транспорта и структура ответа.'),
    ('client/src/apiclient.cpp', 'Асинхронный HTTPS, сертификат, заголовки, JSON и таймаут.'),
    ('client/src/localstore.h', 'Интерфейс локального хранилища и очереди.'),
    ('client/src/localstore.cpp', 'SQLite-кэш, транзакции, offline-операции и разрешение конфликтов.'),
    ('client/src/expensecontroller.h', 'Свойства и действия, доступные интерфейсу QML.'),
    ('client/src/expensecontroller.cpp', 'Бизнес-правила, сессия и последовательность синхронизации.'),
    ('client/qml/com.example.expenseslab2.qml', 'Корневое окно приложения и обложка.'),
    ('client/qml/MainPage.qml', 'Вход, настройки, список, статусы и выбор версии при конфликте.'),
    ('client/qml/ExpenseDialog.qml', 'Форма создания и редактирования расхода.'),
    ('client/com.example.expenseslab2.pro', 'Модули Qt и установка публичного сертификата.'),
    ('client/com.example.expenseslab2.desktop', 'Значок запуска и разрешение Internet.'),
    ('client/rpm/com.example.expenseslab2.spec', 'Сборка и упаковка приложения и тестов в RPM.'),
]


def remove_python_comments(text):
    lines = text.splitlines(keepends=True)
    offsets = [0]
    for line in lines:
        offsets.append(offsets[-1] + len(line))
    spans = []
    for token in tokenize.generate_tokens(io.StringIO(text).readline):
        if token.type == tokenize.COMMENT:
            spans.append((offsets[token.start[0] - 1] + token.start[1], offsets[token.end[0] - 1] + token.end[1]))
    # AST отличает настоящий docstring от строкового литерала в рабочем коде.
    for node in ast.walk(ast.parse(text)):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)) and node.body:
            first = node.body[0]
            if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
                start = offsets[first.lineno - 1] + len(lines[first.lineno - 1].encode()[:first.col_offset].decode())
                end = offsets[first.end_lineno - 1] + len(lines[first.end_lineno - 1].encode()[:first.end_col_offset].decode())
                spans.append((start, end))
    for start, end in sorted(spans, reverse=True):
        text = text[:start] + ''.join('\n' if c == '\n' else ' ' for c in text[start:end]) + text[end:]
    ast.parse(text)
    return text


def remove_c_comments(text):
    # Лексический проход сохраняет URL, escape-последовательности и строки SQL.
    output, index = [], 0
    while index < len(text):
        char = text[index]
        if char in ('"', "'", '`'):
            quote = char
            output.append(char); index += 1
            while index < len(text):
                char = text[index]; output.append(char); index += 1
                if char == '\\' and index < len(text):
                    output.append(text[index]); index += 1
                elif char == quote:
                    break
        elif text.startswith('//', index):
            end = text.find('\n', index)
            index = len(text) if end < 0 else end
        elif text.startswith('/*', index) or text.startswith('<!--', index):
            end_marker = '*/' if text.startswith('/*', index) else '-->'
            end = text.find(end_marker, index)
            end = len(text) if end < 0 else end + len(end_marker)
            output.append(''.join('\n' if c == '\n' else ' ' for c in text[index:end]))
            index = end
        else:
            output.append(char); index += 1
    return ''.join(output)


def listing(path):
    text = (ROOT / path).read_text()
    if path.endswith('.py'):
        text = remove_python_comments(text)
    elif path.endswith(('.pro', '.desktop', '.spec')):
        text = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))
    else:
        text = remove_c_comments(text)
    text = '\n'.join(line.rstrip() for line in text.splitlines()).strip()
    return re.sub(r'\n{3,}', '\n\n', text)


def generate():
    paragraphs = []
    def add(text, style='normal'):
        paragraphs.append((text, style))
    add('ОТЧЁТ', 'title')
    add('по лабораторной работе №2', 'title')
    add('REST API, HTTPS и offline-клиент на Aurora OS', 'title')
    add('Вариант №6 — Расходы', 'title')
    add('Данные титульного листа заполняются студентом.', 'normal')
    add('1. Задание', 'heading')
    task = (ROOT.parent / 'Задания_по_курсу_Разработка_мобильных_и_web_2026.md').read_text()
    task = task.split('**Лабораторная работа №2.', 1)[1].split('Варианты заданий:', 1)[0]
    task = task.split('**', 1)[1].strip().replace('**', '')
    for block in task.split('\n\n'):
        if block.strip(): add(block.strip())
    add('Вариант №6: Расходы. Сервер хранит расходы с полями дата, категория, сумма, комментарий. Приложение позволяет создавать, просматривать, редактировать и удалять расходы, работать offline и синхронизироваться.')
    add('2. Выполнение', 'heading')
    add('Сервер реализован на FastAPI с SQLite и REST API /api/v1/. Клиент — Qt 5.6, QML Silica и C++11 для Авроры 5.2.1.200, armv7hl. Транспорт — HTTPS. Аутентификация — JWT с сохранением токена в QSettings. Сумма хранится целым числом копеек.')
    add('Клиент разделён на интерфейс, контроллер, HTTP-сервис и SQLite-хранилище. Offline-изменения сохраняются в очереди. При восстановлении связи операции отправляются с неизменными ключами идемпотентности. Версии предотвращают молчаливую перезапись конфликтующих правок. Удаления учитываются через tombstones. Кэш обновляется условными запросами с ETag.')
    add('Самостоятельное приложение «Расходы · ЛР2» использует пакет com.example.expenseslab2. Оно устанавливается одновременно с клиентом другой лабораторной. QSettings, локальная SQLite-база и offline-очередь изолированы; данные прежнего пакета com.example.expenses автоматически не переносятся.')
    add('2.1. Основные файлы', 'heading')
    for path, description in FILES:
        add(path, 'heading')
        add(description)
        add(listing(path), 'code')
    add('2.2. Проверка', 'heading')
    add('После разделения два самостоятельных подписанных RPM одновременно установлены на телефон. Оба интерфейса запускаются; пути ресурсов и локальных баз различаются. Повторные нативные тесты SQLite, HTTPS, offline CRUD, восстановления очереди, конфликтов и ETag прошли. Результат: docs/client-separation-validation.txt. Текущий проверенный адрес сервера — https://192.168.0.104:8443; его следует указать в поле адреса приложения.')
    add('Серверные тесты завершились результатом 6 passed. На реальном телефоне прошли нативные проверки SQLite, offline CRUD, сохранения очереди после пересоздания контроллера, HTTPS-синхронизации, разрешения конфликтов и получения 304 по ETag. Подписанный RPM установлен, QML-интерфейс запущен без ошибок загрузки.')
    add('Пользователь подтвердил работу входа и полного CRUD на тестовой HTML-странице в браузере Авроры. Сценарий ручной демонстрации интерфейса и отдельной проверки браузера ПК приведён в docs/VALIDATION.md. Снимки экрана запрещены политикой безопасности устройства; демонстрация проводится на самом телефоне.')
    add('Команды подготовки сертификата, запуска сервера, сборки и установки клиента приведены в README.md.')
    out = ROOT / 'docs'
    md = []
    for text, style in paragraphs:
        if style == 'code': md.append('```\n' + text + '\n```')
        elif style in ('heading', 'title'): md.append('## ' + text)
        else: md.append(text)
    (out / 'REPORT.md').write_text('\n\n'.join(md) + '\n')
    write_docx(out / 'REPORT.docx', paragraphs)


def write_docx(path, paragraphs):
    ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    def tag(s): return '{' + ns + '}' + s
    doc = Element(tag('document')); body = SubElement(doc, tag('body'))
    for text, style in paragraphs:
        # Каждая строка листинга — отдельный параграф: строки сохраняются в Word.
        for line in text.split('\n'):
            p = SubElement(body, tag('p')); pp = SubElement(p, tag('pPr'))
            SubElement(pp, tag('spacing'), {tag('after'): '0' if style == 'code' else '120'})
            if style == 'title': SubElement(pp, tag('jc'), {tag('val'): 'center'})
            if text == '1. Задание': SubElement(pp, tag('pageBreakBefore'))
            r = SubElement(p, tag('r')); rp = SubElement(r, tag('rPr'))
            font = 'Courier New' if style == 'code' else 'Times New Roman'
            SubElement(rp, tag('rFonts'), {tag('ascii'): font, tag('hAnsi'): font, tag('cs'): font})
            SubElement(rp, tag('sz'), {tag('val'): '17' if style == 'code' else '28'})
            if style in ('title', 'heading'): SubElement(rp, tag('b'))
            SubElement(r, tag('t'), {'{http://www.w3.org/XML/1998/namespace}space': 'preserve'}).text = line
    section = SubElement(body, tag('sectPr'))
    SubElement(section, tag('pgSz'), {tag('w'): '11906', tag('h'): '16838'})
    SubElement(section, tag('pgMar'), {tag('top'): '1134', tag('bottom'): '1134', tag('left'): '1701', tag('right'): '850'})
    with ZipFile(path, 'w', ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
        z.writestr('_rels/.rels', '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
        z.writestr('word/document.xml', tostring(doc, encoding='utf-8', xml_declaration=True))


if __name__ == '__main__':
    generate()
    print('Созданы docs/REPORT.md и docs/REPORT.docx; листинги без комментариев.')
