# Сборка нативной части и установка ресурсов, бинарного файла, desktop-файла и иконок в RPM-пакет.
# CMake описывает нативную оболочку Flutter. install копирует артефакты в дерево RPM, а не запускает
# GUI на телефоне.
# This file will be recreated at the next build. To avoid this, delete this line.

# CMAKE_SYSTEM_PROCESSOR - CPU architecture name (armv7l, aarch64, x86_64)
# CMAKE_BUILD_TYPE       - Build mode (debug, profile, release)

cmake_minimum_required(VERSION 3.10)
# Имя бинарного файла берётся из макросов RPM, чтобы совпадать с пакетом.
project(${FLUTTER_PROJECT_NAME} LANGUAGES CXX)

include(GNUInstallDirs)

# Переменная CMake подставляется на этапе конфигурирования, а не во время работы приложения.
set(BINARY_NAME ${CMAKE_PROJECT_NAME})
# Переменная CMake подставляется на этапе конфигурирования, а не во время работы приложения.
set(FLUTTER_DIR ${CMAKE_CURRENT_SOURCE_DIR}/flutter)

# Переменная CMake подставляется на этапе конфигурирования, а не во время работы приложения.
set(CMAKE_CXX_STANDARD 17)
# Переменная CMake подставляется на этапе конфигурирования, а не во время работы приложения.
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Переменная CMake подставляется на этапе конфигурирования, а не во время работы приложения.
set(CMAKE_CXX_FLAGS "-Wall -Wextra")
# Переменная CMake подставляется на этапе конфигурирования, а не во время работы приложения.
set(CMAKE_CXX_FLAGS_RELEASE "-O3")

# Переменная CMake подставляется на этапе конфигурирования, а не во время работы приложения.
set(CMAKE_SKIP_RPATH OFF)
# Переменная CMake подставляется на этапе конфигурирования, а не во время работы приложения.
set(CMAKE_INSTALL_RPATH "\$ORIGIN/../share/${BINARY_NAME}/lib")

# Объявляем нативный исполняемый файл Flutter-оболочки и его исходники.
add_executable(${BINARY_NAME} main.cpp)

# Сгенерированный файл подключает embedder, плагины и нужные библиотеки.
include(flutter/generated_plugins.cmake)

# Переменная CMake подставляется на этапе конфигурирования, а не во время работы приложения.
set(PACKAGE_INSTALL_DIR    ${CMAKE_INSTALL_DATADIR}/${BINARY_NAME})
# Переменная CMake подставляется на этапе конфигурирования, а не во время работы приложения.
set(DESKTOP_INSTALL_DIR    ${CMAKE_INSTALL_DATADIR}/applications)
# Переменная CMake подставляется на этапе конфигурирования, а не во время работы приложения.
set(ICONS_INSTALL_ROOT_DIR ${CMAKE_INSTALL_DATADIR}/icons/hicolor)

# Ресурсы Dart и движок устанавливаются рядом с приложением в share.
# Копируем артефакт в дерево пакета. Это не установка через SSH на телефон.
install(FILES     ${PROJECT_BINARY_DIR}/bundle/icudtl.dat     DESTINATION ${PACKAGE_INSTALL_DIR})
# Копируем артефакт в дерево пакета. Это не установка через SSH на телефон.
install(DIRECTORY ${PROJECT_BINARY_DIR}/bundle/flutter_assets DESTINATION ${PACKAGE_INSTALL_DIR})
# Копируем артефакт в дерево пакета. Это не установка через SSH на телефон.
install(DIRECTORY ${PROJECT_BINARY_DIR}/bundle/lib            DESTINATION ${PACKAGE_INSTALL_DIR})

# Копируем артефакт в дерево пакета. Это не установка через SSH на телефон.
install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
# Копируем артефакт в дерево пакета. Это не установка через SSH на телефон.
install(FILES desktop/${BINARY_NAME}.desktop DESTINATION ${DESKTOP_INSTALL_DIR})

foreach(ICONS_SIZE 86x86 108x108 128x128 172x172)
    # Копируем артефакт в дерево пакета. Это не установка через SSH на телефон.
    install(FILES icons/${ICONS_SIZE}.png
            RENAME ${BINARY_NAME}.png
            DESTINATION ${ICONS_INSTALL_ROOT_DIR}/${ICONS_SIZE}/apps/)
endforeach(ICONS_SIZE)
