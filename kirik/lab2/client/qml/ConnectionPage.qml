// Отдельный экран подключения, учётной записи, offline, диагностики и разрешения конфликтов. Экран
// читает свойства и вызывает действия общего контроллера. Карточки группируют ввод, offline и
// конфликт; реальные HTTP/SQL-операции выполняются в C++.
import QtQuick 2.0
import Sailfish.Silica 1.0

// Экран стека Silica: push открывает следующую страницу, pop возвращает предыдущую. Общие данные
// остаются в контроллере.
Page {
    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
    id: page
    // DarkOnLight задаёт тёмный текст на светлом фоне. Локальная палитра наследуется дочерними элементами.
    palette.colorScheme: Theme.DarkOnLight
    palette.highlightColor: "#1565c0"
    backgroundColor: "#f7f9fc"
    // Ссылка на общий контроллер, а не новая копия сессии или SQLite для этой страницы.
    property var controller: tasksController

    // Прокручиваемая форма: contentHeight должен охватывать поля целиком, иначе нижние элементы окажутся
    // недоступны.
    SilicaFlickable {
        anchors.fill: parent
        // Высота связана с фактическим содержимым и отступами: перенос текста не должен обрезать нижние
        // элементы.
        contentHeight: content.height + Theme.paddingLarge

        // Вертикальная раскладка: элементы идут сверху вниз, spacing задаёт промежуток. Высота зависит от
        // дочернего содержимого.
        Column {
            // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
            id: content
            width: parent.width
            spacing: Theme.paddingLarge
            // Заголовок страницы участвует в её раскладке и навигации. Это не отдельный процесс или контроллер.
            PageHeader { title: "Настройки" }

            // Карточки меняют только представление: действия остаются у контроллера.
            // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
            // отделяют группу полей.
            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                height: accountSummary.height + 2*Theme.paddingLarge
                radius: Theme.paddingLarge
                color: "#e5edff"
                // Вертикальная раскладка: элементы идут сверху вниз, spacing задаёт промежуток. Высота зависит от
                // дочернего содержимого.
                Column {
                    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
                    id: accountSummary
                    x: Theme.paddingLarge; y: x
                    width: parent.width - 2*x
                    spacing: Theme.paddingSmall
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        width: parent.width; wrapMode: Text.Wrap
                        text: controller.authenticated ? controller.username : "Вход не выполнен"
                        font.pixelSize: Theme.fontSizeLarge; font.bold: true
                        color: "#172d40"
                    }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        width: parent.width; wrapMode: Text.Wrap
                        text: controller.offline ? "Локальный режим" : "Обмен с сервером включён"
                        font.pixelSize: Theme.fontSizeSmall; color: "#43566a"
                    }
                }
            }

            // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
            // отделяют группу полей.
            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                height: connectionFields.height + 2*Theme.paddingLarge
                radius: Theme.paddingLarge; color: "white"
                // Вертикальная раскладка: элементы идут сверху вниз, spacing задаёт промежуток. Высота зависит от
                // дочернего содержимого.
                Column {
                    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
                    id: connectionFields
                    y: Theme.paddingLarge; width: parent.width
                    spacing: Theme.paddingMedium
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        x: Theme.paddingLarge; width: parent.width - 2*x
                        text: "01 / Подключение"; color: palette.highlightColor
                        font.bold: true; wrapMode: Text.Wrap
                    }
                    // Однострочный ввод: text хранит исходное значение, enabled блокирует редактирование во время
                    // операции. Окончательную проверку выполняет контроллер.
                    TextField {
                        id: server; width: parent.width
                        label: "Адрес сервера"; placeholderText: "https://<IP-ПК>:8543"
                        text: controller.serverUrl; enabled: !controller.busy
                        inputMethodHints: Qt.ImhUrlCharactersOnly
                    }
                    // Однострочный ввод: text хранит исходное значение, enabled блокирует редактирование во время
                    // операции. Окончательную проверку выполняет контроллер.
                    TextField {
                        id: cert; width: parent.width
                        label: "Доверенный сертификат"; placeholderText: "Полный путь к файлу .crt"
                        text: controller.certificatePath; enabled: !controller.busy
                    }
                }
            }

            // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
            // отделяют группу полей.
            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                height: credentials.height + 2*Theme.paddingLarge
                radius: Theme.paddingLarge; color: "white"
                // Вертикальная раскладка: элементы идут сверху вниз, spacing задаёт промежуток. Высота зависит от
                // дочернего содержимого.
                Column {
                    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
                    id: credentials
                    y: Theme.paddingLarge; width: parent.width
                    spacing: Theme.paddingMedium
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        x: Theme.paddingLarge; width: parent.width - 2*x
                        text: "02 / Учётная запись"; color: palette.highlightColor
                        font.bold: true; wrapMode: Text.Wrap
                    }
                    // Однострочный ввод: text хранит исходное значение, enabled блокирует редактирование во время
                    // операции. Окончательную проверку выполняет контроллер.
                    TextField {
                        id: user; width: parent.width; label: "Пользователь"
                        text: controller.username; enabled: !controller.busy
                    }
                    // Пароль скрывается при отображении. После входа поле очищается; маскировка символов не заменяет TLS.
                    PasswordField {
                        id: password; width: parent.width; label: "Пароль"
                        enabled: !controller.busy
                    }
                    // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
                    // защищает операцию от недопустимого вызова.
                    Button {
                        x: Theme.paddingLarge; width: parent.width - 2*x
                        text: "Войти"; enabled: !controller.busy && !controller.offline
                        onClicked: {
                            controller.login(server.text, user.text, password.text, cert.text)
                            password.text = ""
                        }
                    }
                    // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
                    // защищает операцию от недопустимого вызова.
                    Button {
                        x: Theme.paddingLarge; width: parent.width - 2*x
                        text: "Выйти из учётной записи"
                        enabled: !controller.busy && controller.authenticated
                        onClicked: controller.logout()
                    }
                }
            }

            // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
            // отделяют группу полей.
            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                height: syncSettings.height + 2*Theme.paddingLarge
                radius: Theme.paddingLarge; color: "white"
                // Вертикальная раскладка: элементы идут сверху вниз, spacing задаёт промежуток. Высота зависит от
                // дочернего содержимого.
                Column {
                    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
                    id: syncSettings
                    y: Theme.paddingLarge; width: parent.width
                    spacing: Theme.paddingMedium
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        x: Theme.paddingLarge; width: parent.width - 2*x
                        text: "03 / Синхронизация"; color: palette.highlightColor
                        font.bold: true; wrapMode: Text.Wrap
                    }
                    // Ручной offline-переключатель связан с контроллером. Локальные правки сохраняются, но запросы к
                    // серверу не отправляются.
                    TextSwitch {
                        width: parent.width
                        text: "Работать offline"
                        description: "Не отправлять запросы, сохранять изменения на телефоне"
                        checked: controller.offline; enabled: !controller.busy
                        // Setter меняет режим, сохраняет настройку и согласует сетевой обмен с offline.
                        onClicked: controller.offline = checked
                    }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        x: Theme.paddingLarge; width: parent.width - 2*x
                        text: "В очереди: " + controller.pendingCount
                        font.bold: true; wrapMode: Text.Wrap
                    }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        x: Theme.paddingLarge; width: parent.width - 2*x
                        text: controller.status; wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall; color: "#43566a"
                    }
                    // Анимация ожидания. running запускает индикатор, visible скрывает его при отсутствии операции.
                    BusyIndicator {
                        anchors.horizontalCenter: parent.horizontalCenter
                        size: BusyIndicatorSize.Medium
                        running: controller.busy; visible: running
                    }
                }
            }

            // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
            // отделяют группу полей.
            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                height: conflictContent.height + 2*Theme.paddingLarge
                radius: Theme.paddingLarge; color: "#fff0d8"
                visible: !!controller.conflictInfo.server
                // Вертикальная раскладка: элементы идут сверху вниз, spacing задаёт промежуток. Высота зависит от
                // дочернего содержимого.
                Column {
                    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
                    id: conflictContent
                    x: Theme.paddingLarge; y: x
                    width: parent.width - 2*x
                    spacing: Theme.paddingLarge
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        width: parent.width; text: "Конфликт изменений"
                        font.bold: true; wrapMode: Text.Wrap; color: "#6e4813"
                    }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        width: parent.width; wrapMode: Text.Wrap
                        text: {
                            var info = controller.conflictInfo
                            if (!info.server) return ""
                            var l = info.payload
                            return "На телефоне\n" + l.due_date + " · " + l.title + " · " + l.status + " · " + l.description +
                                    (info.kind === "DELETE" ? " (удаление)" : "")
                        }
                    }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        width: parent.width; wrapMode: Text.Wrap
                        text: {
                            var info = controller.conflictInfo
                            if (!info.server) return ""
                            var s = info.server
                            return "На сервере\n" + s.due_date + " · " + s.title + " · " + s.status + " · " + s.description +
                                    (s.deleted ? " (удалено)" : "")
                        }
                    }
                    // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
                    // защищает операцию от недопустимого вызова.
                    Button {
                        width: parent.width; text: "Принять серверную"
                        enabled: !controller.busy; onClicked: controller.resolve(false)
                    }
                    // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
                    // защищает операцию от недопустимого вызова.
                    Button {
                        width: parent.width; text: "Сохранить локальную"
                        enabled: !controller.busy; onClicked: controller.resolve(true)
                    }
                }
            }
        }
        // Штатный индикатор положения прокрутки. Не меняет модель или сохранённые данные.
        VerticalScrollDecorator {}
    }
}
