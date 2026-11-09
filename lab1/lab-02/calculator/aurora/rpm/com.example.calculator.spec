# RPM spec с генерируемыми макросами defines.inc, зависимостями и командами CMake/Ninja для
# актуального Flutter для Авроры. RPM-макросы %{...} разворачиваются сборщиком. Секции задают
# зависимости, компиляцию, установку в buildroot и перечень содержимого пакета.
%dnl This file will be recreated at the next build. To avoid this, delete this line.

%dnl Flutter генерирует defines.inc из метаданных pubspec.yaml.
# Подключаем generated-макросы Flutter defines.inc, соответствующие текущему SDK.
%include %{_sourcedir}/defines.inc

%global __provides_exclude_from ^%{_datadir}/%{name}/lib/.*$
%global __requires_exclude %{_flutter_excludes}

# Технический идентификатор RPM/приложения; отличается от пользовательского названия.
Name: %{orgName}.%{appName}%{?flavor}
Summary: %{summary}
# Версия функциональности пакета, отдельно от Release пересборки.
Version: %{appVersion}
# Номер пересборки этой версии: позволяет установщику отличать обновлённый пакет.
Release: 1
License: %{license}
# Архив исходников RPM; макросы подставляют имя и версию.
Source0: %{name}-%{version}.tar.zst

%dnl Список BuildRequires собирается Flutter, включая зависимости плагинов.
%requires
%dnl Place to add custom BuildRequires.

%description
%{summary}.

# Подготовка RPM: распаковка Source0 и подготовительные действия.
%prep
%autosetup

# Компиляция в SDK target. Здесь ещё нет установки приложения на телефон.
%build
%cmake -GNinja \
       -DCMAKE_BUILD_TYPE=%{_flutter_build_type} \
       -DPSDK_VERSION=%{_flutter_psdk_version} \
       -DPSDK_MAJOR=%{_flutter_psdk_major} \
       -DFLUTTER_PROJECT_NAME=%{name} \
       -DFLUTTER_ORG_NAME=%{orgName}
%ninja_build

# Установка в временный buildroot будущего RPM.
%install
%ninja_install

# Перечень содержимого RPM: неперечисленный ресурс может не попасть в пакет.
%files
%{_bindir}/%{name}
%{_datadir}/%{name}/*
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
