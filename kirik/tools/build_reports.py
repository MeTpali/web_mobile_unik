"""Цельные отчёты варианта 1: титульник, задание, выполнение, листинги без комментариев."""
from pathlib import Path
from zipfile import ZipFile
import report_support as support

ROOT = Path(__file__).resolve().parents[1]


def files(number):
    root = ROOT / f'lab{number}'
    if number == 1:
        patterns = ['lab-01/server/*.js', 'lab-01/public/*', 'lab-01/package.json',
                    'lab-02/backend/app/*.py', 'lab-02/backend/run.py', 'lab-02/backend/requirements.txt',
                    'lab-02/calculator/lib/**/*.dart', 'lab-02/calculator/pubspec.yaml',
                    'lab-02/calculator/aurora/main.cpp', 'lab-02/calculator/aurora/CMakeLists.txt',
                    'lab-02/calculator/aurora/rpm/*.spec', 'lab-02/calculator/aurora/desktop/*.desktop']
    else:
        patterns = ['backend/app/*.py', 'backend/static/*', 'backend/requirements.txt',
                    'client/src/*.cpp', 'client/src/*.h', 'client/qml/*.qml', 'client/qml/services/*.qml', 'client/services/*.qml',
                    'client/*.pro', 'client/*.desktop', 'client/*.qrc', 'client/rpm/*.spec',
                    'tools/build-client.sh', 'certificates/generate.sh']
        patterns += ['backend/run.py'] if number == 2 else ['deploy/scripts/*', 'deploy/nginx/*', 'deploy/systemd/*', 'tools/sign_package.sh']
    paths = sorted({p for pattern in patterns for p in root.glob(pattern) if p.is_file() and p.stat().st_size})
    descriptions = {
        'main.py': 'API и сетевые обработчики: маршруты, формат обмена и ошибки.',
        'schemas.py': 'JSON-контракт задачи, срок и допустимые статусы.',
        'storage.py': 'Транзакции серверной БД и хранение пользователей.',
        'push.py': 'Межпроцессная доставка событий PostgreSQL в WebSocket.',
        'localstore.cpp': 'SQLite-кэш, устойчивая offline-очередь и разрешение конфликтов.',
        'taskcontroller.cpp': 'Состояние приложения, валидация и последовательность синхронизации.',
        'apiclient.cpp': 'Асинхронный HTTPS-транспорт, JSON, доверие сертификату и повторы.',
        'calculator_controller.dart': 'Контроллер Flutter: ввод, состояние, request_id и история.',
        'calculator_service.dart': 'WebSocket-транспорт Flutter и обработка JSON-кадров.',
        'calculator.py': 'Чистая арифметическая логика с проверкой деления на ноль.',
        'calculator.js': 'Арифметическая логика HTTP-калькулятора.',
        'protocol.py': 'Разбор WebSocket-запроса и формирование ответа с request_id.',
        'SystemNotification.qml': 'Штатные уведомления ОС по task.changed, защита от повторов и замена предыдущей записи.',
        'MainPage.qml': 'Доска задач: сводка по этапам, фильтр, карточки и нижняя панель действий.',
        'ConnectionPage.qml': 'Отдельный экран подключения, учётной записи, offline, диагностики и разрешения конфликтов.',
        'TaskDialog.qml': 'Создание и редактирование заголовка, срока, статуса и описания.',
        'install-host.sh': 'Развёртывание изолированных БД, systemd и nginx.',
        'switch-release.sh': 'Проверка готовности, переключение blue-green и откат.',
        'stage-release.sh': 'Публикация неизменяемой серверной версии.',
        'exercise-cluster.py': 'Реальный сценарий отказа backend, обновления и отката под нагрузкой.',
    }
    return [(str(p.relative_to(ROOT)), descriptions.get(p.name, {
        '.h': 'Интерфейс компонента и доступные свойства.', '.pro': 'Модули Qt и установка ресурсов.',
        '.spec': 'Сборка и упаковка RPM.', '.desktop': 'Идентификатор приложения и разрешения.',
        '.qml': 'Компонент интерфейса или WebSocket-адаптер.', '.dart': 'Модель или интерфейс Flutter.',
        '.conf': 'Конфигурация nginx.', '.service': 'Шаблон запуска backend через systemd.',
        '.html': 'Браузерный интерфейс.', '.js': 'HTTP-транспорт или обработка действий пользователя.',
        '.css': 'Адаптивное оформление с @media.', '.sh': 'Сценарий подготовки и сборки.',
    }.get(p.suffix, 'Настройки и зависимости компонента.'))) for p in paths]


def generate():
    out = ROOT / 'reports'; out.mkdir(exist_ok=True)
    with ZipFile(ROOT / 'tools/report_template.docx') as archive:
        template = {name: archive.read(name) for name in archive.namelist()}
    titles = ['Взаимодействие с web-клиентом и WebSockets: калькулятор',
              'REST API, HTTPS и offline-клиент: список задач',
              'Сборка, подпись, деплой и масштабирование: список задач']
    for number in (1, 2, 3):
        domain = 'Простой калькулятор' if number == 1 else 'Список задач'
        text = support.title(number, titles[number-1], domain)
        text += '\n\n# 1. Задание\n\n' + support.task(number)
        text += '\n\nВариант №1: ' + ('два числа и операции +, −, *, /.' if number == 1 else 'задача с заголовком, описанием, статусом и сроком; CRUD, offline и синхронизация.')
        text += '\n\n# 2. Выполнение\n\n## 2.1. Архитектура и реализация\n\n'
        text += (ROOT / f'lab{number}/EXPLANATION.md').read_text().split('\n', 1)[1].strip()
        if number > 1:
            text += f'\n\nСамостоятельный пакет ru.kirik.taskslab{number}; данные и настройки отделены от другого клиента. UI реализован на QML, логика — C++11/Qt 5.6, сервер — FastAPI. Сертификат проверяется по цепочке доверия и имени хоста.'
        text += '\n\n## 2.3. Основные файлы\n\n' + support.sources(files(number))
        text += '\n\n## 2.4. Запуск и результаты\n\n'
        validation = ROOT / f'lab{number}/docs/VALIDATION.md'
        text += validation.read_text().split('\n', 1)[1].strip() if validation.exists() else 'Результаты проверок фиксируются отдельно; отсутствие записи не означает успешную проверку.'
        text += f'\n\nПорядок подготовки, запуска и полной демонстрации: lab{number}/README.md и lab{number}/DEMONSTRATION.md. Учётные данные для задач: demo / demo12345. Титульный лист заполняется студентом.\n'
        path = out / f'Отчёт_ЛР_{number:02}'
        path.with_suffix('.md').write_text(text)
        support.docx(path.with_suffix('.docx'), text, template)
        print(f'ЛР{number}: {len(files(number))} основных файлов, MD/DOCX')


if __name__ == '__main__':
    generate()
