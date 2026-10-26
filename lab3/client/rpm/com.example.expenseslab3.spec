Name: com.example.expenseslab3
Summary: Scalable expenses — laboratory 3
Version: 2.0.0
Release: 10
License: BSD-3-Clause
URL: https://developer.auroraos.ru
Source0: %{name}-%{version}.tar.bz2
Requires: sailfishsilica-qt5 >= 0.10.9
Requires: qt5-plugin-sqldriver-sqlite
Requires: qt5-qtwebsockets
Requires: qt5-qtdeclarative-import-websockets
Requires: nemo-qml-plugin-notifications-qt5
BuildRequires: pkgconfig(auroraapp)
BuildRequires: pkgconfig(Qt5Core)
BuildRequires: pkgconfig(Qt5Qml)
BuildRequires: pkgconfig(Qt5Quick)
BuildRequires: pkgconfig(Qt5Network)
BuildRequires: pkgconfig(Qt5Sql)

%description
REST HTTPS client with SQLite cache and persistent offline synchronization.

%prep
%autosetup

%build
%qmake5
make %{?_smp_mflags}
(cd tests && qmake -qt=5 tests.pro && make %{?_smp_mflags})

%install
%qmake5_install
install -Dm755 tests/expenses-tests %{buildroot}%{_bindir}/com.example.expenseslab3-tests

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_bindir}/com.example.expenseslab3-tests
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png

%changelog
* Sun Oct 25 2026 Student <student@example.com> - 1.0.0-1
- Initial laboratory implementation.
