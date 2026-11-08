// Доска задач: сводка по этапам, фильтр, карточки и нижняя панель действий. QML декларативно описывает
// дерево. Выражения свойств — привязки; onClicked вызывается при действии пользователя. Theme задаёт
// размеры с учётом плотности экрана.
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
    allowedOrientations: Orientation.All
    // Ссылка на общий контроллер, а не новая копия сессии или SQLite для этой страницы.
    property var controller: tasksController
    // Номер фильтра сопоставляется с доменным статусом, 0 означает все записи.
    property int selectedStatus: 0
    // Фильтруется только представление; исходные данные остаются в контроллере.
    // Фильтруем только модель представления. Смена фильтра не удаляет строки исходного кэша.
    property var visibleTasks: {
        var rows = controller.tasks
        if (selectedStatus === 0) return rows
        var state = ["", "todo", "doing", "done"][selectedStatus]
        return rows.filter(function (row) { return row.status === state })
    }
    // Прокручиваемый список создаёт delegate по модели контроллера. Сам список не читает SQL и не делает
    // сетевые запросы.
    SilicaListView {
        // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
        id: list
        anchors { fill: parent; bottomMargin: toolbar.height }
        model: page.visibleTasks
        spacing: Theme.paddingMedium
        header: Column {
            width: list.width
            spacing: Theme.paddingMedium
            // Заголовок страницы участвует в её раскладке и навигации. Это не отдельный процесс или контроллер.
            PageHeader { title: "Задачи ЛР3" }
            // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
            // отделяют группу полей.
            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                height: connections.height + 2*Theme.paddingLarge
                radius: Theme.paddingLarge; color: "#e8eef8"
                // Вертикальная раскладка: элементы идут сверху вниз, spacing задаёт промежуток. Высота зависит от
                // дочернего содержимого.
                Column {
                    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
                    id: connections
                    x: Theme.paddingLarge; y: x; width: parent.width - 2*x
                    spacing: Theme.paddingMedium
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label { text: "Соединения"; font.bold: true; color: "#172d40" }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        width: parent.width; text: controller.serverUrl
                        wrapMode: Text.Wrap; font.pixelSize: Theme.fontSizeSmall; color: "#43566a"
                    }
                    // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
                    // отделяют группу полей.
                    Rectangle { width: parent.width; height: 1; color: "#cbd6e7" }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        width: parent.width; wrapMode: Text.Wrap
                        text: "Данные · REST"; font.bold: true; color: "#24477e"
                    }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        width: parent.width; wrapMode: Text.Wrap
                        // REST показывает последний полученный backend. Это история запроса, в отличие от постоянного
                        // WSS-соединения.
                        text: controller.backend || "Ответов от сервера ещё нет"
                        color: "#172d40"
                    }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        width: parent.width; wrapMode: Text.Wrap
                        text: controller.offline ? "Offline · показан последний ответ" :
                              !controller.authenticated ? "Требуется вход" :
                              controller.busy ? "Выполняется запрос…" : "Backend последнего ответа; следующий может отличаться"
                        font.pixelSize: Theme.fontSizeExtraSmall; color: "#43566a"
                    }
                    // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
                    // отделяют группу полей.
                    Rectangle { width: parent.width; height: 1; color: "#cbd6e7" }
                    // Горизонтальная раскладка. Ширины и spacing должны суммарно помещаться в родительскую область.
                    Row {
                        spacing: Theme.paddingSmall
                        // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
                        // отделяют группу полей.
                        Rectangle {
                            width: Theme.paddingMedium; height: width; radius: width/2
                            anchors.verticalCenter: parent.verticalCenter
                            color: controller.pushBackend.length > 0 ? "#24865e" : "#9b7032"
                        }
                        // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                        // экрана.
                        Label { text: "Уведомления · WSS"; font.bold: true; color: "#24477e" }
                    }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        width: parent.width; wrapMode: Text.Wrap
                        // Показываем только активный авторизованный WSS-backend; при его отсутствии выводим состояние
                        // ожидания/отключения.
                        text: controller.pushBackend || (controller.offline ? "Отключено · offline" :
                              !controller.authenticated ? "Ожидание входа" : controller.pushStatus)
                        color: "#172d40"
                    }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        width: parent.width; wrapMode: Text.Wrap
                        // Показываем только активный авторизованный WSS-backend; при его отсутствии выводим состояние
                        // ожидания/отключения.
                        text: controller.pushBackend ? "Активное соединение · событий: " + controller.pushCount : "Автоматическое подключение при работе online"
                        font.pixelSize: Theme.fontSizeExtraSmall; color: "#43566a"
                    }
                }
            }

            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: "Мой план"; font.pixelSize: Theme.fontSizeExtraLarge; font.bold: true
            }
            // Горизонтальная раскладка. Ширины и spacing должны суммарно помещаться в родительскую область.
            Row {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                spacing: Theme.paddingSmall
                // Создаёт элемент для каждого значения модели. index — позиция, modelData — данные именно этого
                // экземпляра.
                Repeater {
                    model: ["todo", "doing", "done"]
                    // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
                    // отделяют группу полей.
                    Rectangle {
                        width: (parent.width - 2*Theme.paddingSmall)/3
                        height: Theme.itemSizeLarge
                        radius: Theme.paddingMedium
                        color: ["#e5edff", "#fff0d8", "#ddf3e9"][index]
                        // Вертикальная раскладка: элементы идут сверху вниз, spacing задаёт промежуток. Высота зависит от
                        // дочернего содержимого.
                        Column {
                            anchors.centerIn: parent
                            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                            // экрана.
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: controller.tasks.filter(function (r) { return r.status === modelData }).length
                                font.pixelSize: Theme.fontSizeLarge; font.bold: true; color: "#172d40"
                            }
                            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                            // экрана.
                            Label { text: ["В планах", "В работе", "Готово"][index]; font.pixelSize: Theme.fontSizeExtraSmall; color: "#33495a" }
                        }
                    }
                }
            }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: !controller.authenticated ? "Откройте подключение, чтобы войти" :
                      (controller.offline ? "Локальный режим" : "Работа с сервером") + " · В очереди: " + controller.pendingCount
                wrapMode: Text.Wrap; font.pixelSize: Theme.fontSizeSmall; color: "#43566a"
            }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: controller.status; wrapMode: Text.Wrap; font.pixelSize: Theme.fontSizeSmall
                color: palette.highlightColor
            }
            // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
            // защищает операцию от недопустимого вызова.
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !!controller.conflictInfo.server
                text: "Разобрать конфликт"
                // Открываем страницу через стек. Для редактирования передаём record с исходными полями/id.
                onClicked: pageStack.push(Qt.resolvedUrl("ConnectionPage.qml"))
            }
            // Выбор из фиксированного списка. currentIndex сопоставляется с доменным статусом, а на сервер
            // отправляется значение, не русский перевод.
            ComboBox {
                width: parent.width; label: "Показать"; currentIndex: page.selectedStatus
                onCurrentIndexChanged: page.selectedStatus = currentIndex
                menu: ContextMenu {
                    // Пункт выбора с обработчиком действия. Значения относятся к текущему меню/записи delegate.
                    MenuItem { text: "Все задачи" }
                    // Пункт выбора с обработчиком действия. Значения относятся к текущему меню/записи delegate.
                    MenuItem { text: "В планах" }
                    // Пункт выбора с обработчиком действия. Значения относятся к текущему меню/записи delegate.
                    MenuItem { text: "В работе" }
                    // Пункт выбора с обработчиком действия. Значения относятся к текущему меню/записи delegate.
                    MenuItem { text: "Готово" }
                }
            }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                visible: list.count === 0
                text: page.selectedStatus ? "В этой группе пока пусто" : "Начните с новой задачи"
                wrapMode: Text.Wrap
            }
        }
        delegate: ListItem {
            // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
            id: entry
            // Закрепляем данные текущей строки delegate. Обработчики используют её id даже после изменения порядка
            // отображения.
            property var row: modelData
            // Высота связана с фактическим содержимым и отступами: перенос текста не должен обрезать нижние
            // элементы.
            contentHeight: cardContent.height + 3*Theme.paddingLarge
            // Открываем страницу через стек. Для редактирования передаём record с исходными полями/id.
            onClicked: if (controller.authenticated && !controller.busy) pageStack.push(Qt.resolvedUrl("TaskDialog.qml"), {record: row})
            // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
            // отделяют группу полей.
            Rectangle {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                height: parent.contentHeight - Theme.paddingSmall
                radius: Theme.paddingLarge; color: "white"
                // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
                // отделяют группу полей.
                Rectangle {
                    x: 0; y: Theme.paddingLarge; width: Theme.paddingSmall; height: Theme.itemSizeSmall
                    radius: width/2
                    // Цвет этапа определяется доменным статусом. Текст статуса рядом нужен, чтобы смысл не передавался
                    // одним цветом.
                    color: ({todo: "#3875df", doing: "#c17b18", done: "#24865e"})[entry.row.status] || "#3875df"
                }
                // Вертикальная раскладка: элементы идут сверху вниз, spacing задаёт промежуток. Высота зависит от
                // дочернего содержимого.
                Column {
                    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
                    id: cardContent
                    x: Theme.paddingLarge; y: Theme.paddingLarge
                    width: parent.width - 2*x; spacing: Theme.paddingSmall
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label { width: parent.width; text: entry.row.title; font.bold: true; wrapMode: Text.Wrap }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label { width: parent.width; text: "Срок: " + entry.row.due_date; font.pixelSize: Theme.fontSizeSmall; color: "#52677a"; wrapMode: Text.Wrap }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label {
                        width: parent.width
                        text: ({todo: "В планах", doing: "В работе", done: "Готово"})[entry.row.status] +
                              (entry.row.conflict ? " · конфликт" : entry.row.pending ? " · ожидает отправки" : "")
                        font.pixelSize: Theme.fontSizeSmall; color: palette.highlightColor; wrapMode: Text.Wrap
                    }
                    // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
                    // экрана.
                    Label { width: parent.width; text: entry.row.description; visible: text.length > 0; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.Wrap }
                    // Горизонтальная раскладка. Ширины и spacing должны суммарно помещаться в родительскую область.
                    Row {
                        width: parent.width; spacing: Theme.paddingMedium
                        // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
                        // защищает операцию от недопустимого вызова.
                        Button {
                            width: (parent.width - Theme.paddingMedium)/2; text: "Изменить"
                            enabled: controller.authenticated && !controller.busy
                            // Открываем страницу через стек. Для редактирования передаём record с исходными полями/id.
                            onClicked: pageStack.push(Qt.resolvedUrl("TaskDialog.qml"), {record: entry.row})
                        }
                        // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
                        // защищает операцию от недопустимого вызова.
                        Button {
                            width: (parent.width - Theme.paddingMedium)/2; text: "Удалить"
                            enabled: controller.authenticated && !controller.busy
                            // Отложенное удаление допускает отмену; затем контроллер поставит операцию в outbox.
                            onClicked: entry.remorseAction("Удаление задачи", function () { controller.remove(entry.row.id) })
                        }
                    }
                }
            }
        }
        // Штатный индикатор положения прокрутки. Не меняет модель или сохранённые данные.
        VerticalScrollDecorator {}
    }
    // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
    // отделяют группу полей.
    Rectangle {
        // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
        id: toolbar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: actions.height + 2*Theme.paddingMedium; color: "#e8eef8"
        // Горизонтальная раскладка. Ширины и spacing должны суммарно помещаться в родительскую область.
        Row {
            // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
            id: actions
            x: Theme.paddingMedium; y: Theme.paddingMedium
            width: parent.width - 2*x; spacing: Theme.paddingSmall
            // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
            // защищает операцию от недопустимого вызова.
            Button {
                width: (parent.width - 2*Theme.paddingSmall)/3; text: "Настройки"
                // Открываем страницу через стек. Для редактирования передаём record с исходными полями/id.
                onClicked: pageStack.push(Qt.resolvedUrl("ConnectionPage.qml"))
            }
            // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
            // защищает операцию от недопустимого вызова.
            Button {
                width: (parent.width - 2*Theme.paddingSmall)/3; text: "Обновить"
                enabled: controller.authenticated && !controller.offline && !controller.busy
                onClicked: controller.sync()
            }
            // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
            // защищает операцию от недопустимого вызова.
            Button {
                width: (parent.width - 2*Theme.paddingSmall)/3; text: "+ Задача"
                enabled: controller.authenticated && !controller.busy
                // Открываем страницу через стек. Для редактирования передаём record с исходными полями/id.
                onClicked: pageStack.push(Qt.resolvedUrl("TaskDialog.qml"))
            }
        }
    }
}
