# Модули Qt и установка ресурсов. qmake выбирает модули Qt, исходники C++ и правила установки. Это
# настройки сборки, не runtime-конфигурация пользователя.
# Имя бинарника и основа идентификатора ресурсов. Должно согласовываться с desktop и RPM Name.
TARGET = ru.kirik.taskslab3
# qmake подключает правила auroraapp и выбранный стандарт C++.
CONFIG += auroraapp c++11
# Модули Qt: network — HTTPS, sql — SQLite. Include без линковки модуля недостаточно.
QT += network sql
# Коллекция Qt-ресурсов делает QML-адаптеры доступными по qrc:/ независимо от текущего каталога.
RESOURCES += services.qrc
# Компилируемые .cpp: каждый становится частью бинарника; заголовки не компилируются отдельно.
SOURCES += src/main.cpp src/apiclient.cpp src/localstore.cpp src/taskcontroller.cpp
# Компилируемые .cpp: каждый становится частью бинарника; заголовки не компилируются отдельно.
SOURCES += src/pushservice.cpp
# Объявления интерфейсов, также необходимые moc для классов с Q_OBJECT.
HEADERS += src/apiclient.h src/localstore.h src/taskcontroller.h
# Объявления интерфейсов, также необходимые moc для классов с Q_OBJECT.
HEADERS += src/pushservice.h
# Имена каталогов hicolor. Размер записывается как 86x86, иначе оболочка не найдёт иконку по имени.
AURORAAPP_ICONS = 86x86
certificates.files = ../certificates/server.crt
certificates.path = /usr/share/$${TARGET}/certificates
# Группы файлов этапа установки в дерево будущего RPM.
INSTALLS += certificates
DISTFILES += rpm/ru.kirik.taskslab3.spec
