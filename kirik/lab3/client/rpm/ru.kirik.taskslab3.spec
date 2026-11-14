# Сборка и упаковка RPM. RPM-макросы %{...} разворачиваются сборщиком. Секции задают зависимости,
# компиляцию, установку в buildroot и перечень содержимого пакета.
# Технический идентификатор RPM/приложения; отличается от пользовательского названия.
Name: ru.kirik.taskslab3
Summary: Scalable tasks — laboratory 3
# Версия функциональности пакета, отдельно от Release пересборки.
Version: 2.0.0
# Номер пересборки этой версии: позволяет установщику отличать обновлённый пакет.
Release: 20
License: BSD-3-Clause
URL: https://developer.auroraos.ru
# Архив исходников RPM; макросы подставляют имя и версию.
Source0: %{name}-%{version}.tar.bz2
# Runtime-зависимость: должна быть доступна на устройстве при запуске.
Requires: sailfishsilica-qt5 >= 0.10.9
# Runtime-зависимость: должна быть доступна на устройстве при запуске.
Requires: qt5-plugin-sqldriver-sqlite
# Runtime-зависимость: должна быть доступна на устройстве при запуске.
Requires: qt5-qtwebsockets
# Runtime-зависимость: должна быть доступна на устройстве при запуске.
Requires: qt5-qtdeclarative-import-websockets
# Runtime-зависимость: должна быть доступна на устройстве при запуске.
Requires: nemo-qml-plugin-notifications-qt5
# Зависимость сборки внутри SDK/target, не обязательно инструмент телефона.
BuildRequires: pkgconfig(auroraapp)
# Зависимость сборки внутри SDK/target, не обязательно инструмент телефона.
BuildRequires: pkgconfig(Qt5Core)
# Зависимость сборки внутри SDK/target, не обязательно инструмент телефона.
BuildRequires: pkgconfig(Qt5Qml)
# Зависимость сборки внутри SDK/target, не обязательно инструмент телефона.
BuildRequires: pkgconfig(Qt5Quick)
# Зависимость сборки внутри SDK/target, не обязательно инструмент телефона.
BuildRequires: pkgconfig(Qt5Network)
# Зависимость сборки внутри SDK/target, не обязательно инструмент телефона.
BuildRequires: pkgconfig(Qt5Sql)

%description
REST HTTPS client with SQLite cache and persistent offline synchronization.

# Подготовка RPM: распаковка Source0 и подготовительные действия.
%prep
%autosetup

# Компиляция в SDK target. Здесь ещё нет установки приложения на телефон.
%build
%qmake5
make %{?_smp_mflags}
(cd tests && qmake -qt=5 tests.pro && make %{?_smp_mflags})

# Установка в временный buildroot будущего RPM.
%install
%qmake5_install
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -Dm755 tests/tasks-tests %{buildroot}%{_bindir}/ru.kirik.taskslab3-tests

# Перечень содержимого RPM: неперечисленный ресурс может не попасть в пакет.
%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_bindir}/ru.kirik.taskslab3-tests
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png

# История изменений RPM, не исполняемый код.
%changelog
* Sun Oct 25 2026 Student <student@example.com> - 1.0.0-1
- Initial laboratory implementation.
