# Модули Qt и установка публичного сертификата. qmake выбирает модули Qt, исходники C++ и правила
# установки. Это настройки сборки, не runtime-конфигурация пользователя.
# Имя бинарника и основа идентификатора ресурсов. Должно согласовываться с desktop и RPM Name.
TARGET = com.example.expenseslab2
# qmake подключает правила auroraapp и выбранный стандарт C++.
CONFIG += auroraapp c++11
# Модули Qt: network — HTTPS, sql — SQLite. Include без линковки модуля недостаточно.
QT += network sql
# Компилируемые .cpp: каждый становится частью бинарника; заголовки не компилируются отдельно.
SOURCES += src/main.cpp src/apiclient.cpp src/localstore.cpp src/expensecontroller.cpp
# Объявления интерфейсов, также необходимые moc для классов с Q_OBJECT.
HEADERS += src/apiclient.h src/localstore.h src/expensecontroller.h
# Имена каталогов hicolor. Размер записывается как 86x86, иначе оболочка не найдёт иконку по имени.
AURORAAPP_ICONS = 86
certificates.files = ../certificates/server.crt
certificates.path = /usr/share/$${TARGET}/certificates
# Группы файлов этапа установки в дерево будущего RPM.
INSTALLS += certificates
DISTFILES += rpm/com.example.expenseslab2.spec
