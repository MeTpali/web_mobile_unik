// Вход, настройки, список, статусы и выбор версии при конфликте. QML декларативно описывает дерево.
// Выражения свойств — привязки; onClicked вызывается при действии пользователя. Theme задаёт размеры с
// учётом плотности экрана.
import QtQuick 2.0
import Sailfish.Silica 1.0

// Экран стека Silica: push открывает следующую страницу, pop возвращает предыдущую. Общие данные
// остаются в контроллере.
Page {
    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
    id: page
    allowedOrientations: Orientation.All
    // Ссылка на общий контроллер, а не новая копия сессии или SQLite для этой страницы.
    property var controller: expensesController
    // Прокручиваемый список создаёт delegate по модели контроллера. Сам список не читает SQL и не делает
    // сетевые запросы.
    SilicaListView {
        // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
        id: list
        anchors.fill: parent
        // Модель читается из контроллера. При changed привязка пересчитывается и список отражает актуальный
        // кэш.
        model: controller.expenses
        PullDownMenu {
            // Пункт выбора с обработчиком действия. Значения относятся к текущему меню/записи delegate.
            MenuItem { text: "Новый расход"; enabled: !controller.busy && controller.authenticated; onClicked: pageStack.push(Qt.resolvedUrl("ExpenseDialog.qml")) }
            // Пункт выбора с обработчиком действия. Значения относятся к текущему меню/записи delegate.
            MenuItem { text: "Синхронизировать"; enabled: !controller.busy && controller.authenticated && !controller.offline; onClicked: controller.sync() }
        }
        header: Column {
            width: list.width
            // Заголовок страницы участвует в её раскладке и навигации. Это не отдельный процесс или контроллер.
            PageHeader { title: "Расходы ЛР3" }
            // Подпись смысловой группы полей, визуально разделяющая настройки.
            SectionHeader { text: "Сервер и вход" }
            // Однострочный ввод: text хранит исходное значение, enabled блокирует редактирование во время
            // операции. Окончательную проверку выполняет контроллер.
            TextField { id: server; width: parent.width; label: "HTTPS-адрес ПК"; text: controller.serverUrl; enabled: !controller.busy; inputMethodHints: Qt.ImhUrlCharactersOnly }
            // Однострочный ввод: text хранит исходное значение, enabled блокирует редактирование во время
            // операции. Окончательную проверку выполняет контроллер.
            TextField { id: user; width: parent.width; label: "Пользователь"; text: controller.username; enabled: !controller.busy }
            // Пароль скрывается при отображении. После входа поле очищается; маскировка символов не заменяет TLS.
            PasswordField { id: password; width: parent.width; label: "Пароль"; enabled: !controller.busy }
            // Однострочный ввод: text хранит исходное значение, enabled блокирует редактирование во время
            // операции. Окончательную проверку выполняет контроллер.
            TextField { id: cert; width: parent.width; label: "Путь к доверенному сертификату"; text: controller.certificatePath; enabled: !controller.busy }
            // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
            // защищает операцию от недопустимого вызова.
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Войти"; enabled: !controller.busy && !controller.offline
                onClicked: { controller.login(server.text, user.text, password.text, cert.text); password.text = "" }
            }
            // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
            // защищает операцию от недопустимого вызова.
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Выйти"; enabled: !controller.busy && controller.authenticated
                onClicked: controller.logout()
            }
            // Ручной offline-переключатель связан с контроллером. Локальные правки сохраняются, но запросы к
            // серверу не отправляются.
            TextSwitch { text: "Работать offline"; description: "Не отправлять запросы, сохранять изменения на телефоне"; checked: controller.offline; enabled: !controller.busy; onClicked: controller.offline = checked }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: controller.status; wrapMode: Text.Wrap; color: Theme.highlightColor
            }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: controller.pushStatus + "\nREST: " + controller.backend
                wrapMode: Text.Wrap; font.pixelSize: Theme.fontSizeSmall
            }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                visible: controller.pushCount > 0
                text: "Push-событий: " + controller.pushCount + " · " + controller.lastPush
                wrapMode: Text.Wrap; color: Theme.highlightColor
            }
            // Анимация ожидания. running запускает индикатор, visible скрывает его при отсутствии операции.
            BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; size: BusyIndicatorSize.Medium; running: controller.busy; visible: running }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: "Изменений в очереди: " + controller.pendingCount; wrapMode: Text.Wrap
            }
            // Вертикальная раскладка: элементы идут сверху вниз, spacing задаёт промежуток. Высота зависит от
            // дочернего содержимого.
            Column {
                width: parent.width
                visible: !!controller.conflictInfo.server
                // Подпись смысловой группы полей, визуально разделяющая настройки.
                SectionHeader { text: "Конфликт изменений" }
                // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                // экрана.
                Label {
                    x: Theme.horizontalPageMargin; width: parent.width - 2*x; wrapMode: Text.Wrap
                    text: {
                        var info = controller.conflictInfo
                        if (!info.server) return ""
                        var s = info.server, l = info.payload
                        return "Локально: " + l.date + " · " + l.category + " · " + (l.amount_minor/100).toFixed(2) + " ₽ · " + l.comment + (info.kind === "DELETE" ? " (удаление)" : "") +
                                "\nНа сервере: " + s.date + " · " + s.category + " · " + (s.amount_minor/100).toFixed(2) + " ₽ · " + s.comment + (s.deleted ? " (удалено)" : "")
                    }
                }
                // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
                // защищает операцию от недопустимого вызова.
                Button { text: "Принять серверную"; anchors.horizontalCenter: parent.horizontalCenter; enabled: !controller.busy; onClicked: controller.resolve(false) }
                // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
                // защищает операцию от недопустимого вызова.
                Button { text: "Сохранить локальную"; anchors.horizontalCenter: parent.horizontalCenter; enabled: !controller.busy; onClicked: controller.resolve(true) }
            }
            // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
            // защищает операцию от недопустимого вызова.
            Button {
                anchors.horizontalCenter: parent.horizontalCenter; text: "Новый расход"
                enabled: !controller.busy && controller.authenticated
                // Открываем страницу через стек. Для редактирования передаём record с исходными полями/id.
                onClicked: pageStack.push(Qt.resolvedUrl("ExpenseDialog.qml"))
            }
            // Подпись смысловой группы полей, визуально разделяющая настройки.
            SectionHeader { text: "Сохранённые расходы" }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label { x: Theme.horizontalPageMargin; text: "Пока нет расходов"; visible: list.count === 0 }
        }
        delegate: ListItem {
            // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
            id: entry
            // Закрепляем данные текущей строки delegate. Обработчики используют её id даже после изменения порядка
            // отображения.
            property var row: modelData
            // Высота связана с фактическим содержимым и отступами: перенос текста не должен обрезать нижние
            // элементы.
            contentHeight: details.height + 2*Theme.paddingMedium
            enabled: !controller.busy && controller.authenticated
            // Открываем страницу через стек. Для редактирования передаём record с исходными полями/id.
            onClicked: pageStack.push(Qt.resolvedUrl("ExpenseDialog.qml"), {record: row})
            menu: ContextMenu {
                // Пункт выбора с обработчиком действия. Значения относятся к текущему меню/записи delegate.
                MenuItem { text: "Редактировать"; onClicked: pageStack.push(Qt.resolvedUrl("ExpenseDialog.qml"), {record: entry.row}) }
                // Пункт выбора с обработчиком действия. Значения относятся к текущему меню/записи delegate.
                MenuItem { text: "Удалить"; onClicked: entry.remorseAction("Удаление", function () { controller.remove(entry.row.id) }) }
            }
            // Вертикальная раскладка: элементы идут сверху вниз, spacing задаёт промежуток. Высота зависит от
            // дочернего содержимого.
            Column {
                id: details; x: Theme.horizontalPageMargin; width: parent.width - 2*x; y: Theme.paddingMedium
                // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                // экрана.
                Label { width: parent.width; text: row.date + " · " + row.category; wrapMode: Text.Wrap; color: Theme.highlightColor }
                // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                // экрана.
                Label { width: parent.width; text: (row.amount_minor/100).toFixed(2) + " ₽" + (row.conflict ? " · конфликт" : row.pending ? " · не отправлено" : ""); wrapMode: Text.Wrap }
                // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                // экрана.
                Label { width: parent.width; text: row.comment; visible: text.length > 0; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.Wrap }
            }
        }
        // Штатный индикатор положения прокрутки. Не меняет модель или сохранённые данные.
        VerticalScrollDecorator {}
    }
}
