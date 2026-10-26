import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    palette.colorScheme: Theme.DarkOnLight
    palette.highlightColor: "#1565c0"
    backgroundColor: "#f7f9fc"
    allowedOrientations: Orientation.All
    property var controller: tasksController
    property int selectedStatus: 0
    // Фильтруется только представление; исходные данные остаются в контроллере.
    property var visibleTasks: {
        var rows = controller.tasks
        if (selectedStatus === 0) return rows
        var state = ["", "todo", "doing", "done"][selectedStatus]
        return rows.filter(function (row) { return row.status === state })
    }
    SilicaListView {
        id: list
        anchors { fill: parent; bottomMargin: toolbar.height }
        model: page.visibleTasks
        spacing: Theme.paddingMedium
        header: Column {
            width: list.width
            spacing: Theme.paddingMedium
            PageHeader { title: "Задачи ЛР2" }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: "Мой план"; font.pixelSize: Theme.fontSizeExtraLarge; font.bold: true
            }
            Row {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                spacing: Theme.paddingSmall
                Repeater {
                    model: ["todo", "doing", "done"]
                    Rectangle {
                        width: (parent.width - 2*Theme.paddingSmall)/3
                        height: Theme.itemSizeLarge
                        radius: Theme.paddingMedium
                        color: ["#e5edff", "#fff0d8", "#ddf3e9"][index]
                        Column {
                            anchors.centerIn: parent
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: controller.tasks.filter(function (r) { return r.status === modelData }).length
                                font.pixelSize: Theme.fontSizeLarge; font.bold: true; color: "#172d40"
                            }
                            Label { text: ["В планах", "В работе", "Готово"][index]; font.pixelSize: Theme.fontSizeExtraSmall; color: "#33495a" }
                        }
                    }
                }
            }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: !controller.authenticated ? "Откройте подключение, чтобы войти" :
                      (controller.offline ? "Локальный режим" : "Работа с сервером") + " · В очереди: " + controller.pendingCount
                wrapMode: Text.Wrap; font.pixelSize: Theme.fontSizeSmall; color: "#43566a"
            }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: controller.status; wrapMode: Text.Wrap; font.pixelSize: Theme.fontSizeSmall
                color: palette.highlightColor
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !!controller.conflictInfo.server
                text: "Разобрать конфликт"
                onClicked: pageStack.push(Qt.resolvedUrl("ConnectionPage.qml"))
            }
            ComboBox {
                width: parent.width; label: "Показать"; currentIndex: page.selectedStatus
                onCurrentIndexChanged: page.selectedStatus = currentIndex
                menu: ContextMenu {
                    MenuItem { text: "Все задачи" }
                    MenuItem { text: "В планах" }
                    MenuItem { text: "В работе" }
                    MenuItem { text: "Готово" }
                }
            }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                visible: list.count === 0
                text: page.selectedStatus ? "В этой группе пока пусто" : "Начните с новой задачи"
                wrapMode: Text.Wrap
            }
        }
        delegate: ListItem {
            id: entry
            property var row: modelData
            contentHeight: cardContent.height + 3*Theme.paddingLarge
            onClicked: if (controller.authenticated && !controller.busy) pageStack.push(Qt.resolvedUrl("TaskDialog.qml"), {record: row})
            Rectangle {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                height: parent.contentHeight - Theme.paddingSmall
                radius: Theme.paddingLarge; color: "white"
                Rectangle {
                    x: 0; y: Theme.paddingLarge; width: Theme.paddingSmall; height: Theme.itemSizeSmall
                    radius: width/2
                    color: ({todo: "#3875df", doing: "#c17b18", done: "#24865e"})[entry.row.status] || "#3875df"
                }
                Column {
                    id: cardContent
                    x: Theme.paddingLarge; y: Theme.paddingLarge
                    width: parent.width - 2*x; spacing: Theme.paddingSmall
                    Label { width: parent.width; text: entry.row.title; font.bold: true; wrapMode: Text.Wrap }
                    Label { width: parent.width; text: "Срок: " + entry.row.due_date; font.pixelSize: Theme.fontSizeSmall; color: "#52677a"; wrapMode: Text.Wrap }
                    Label {
                        width: parent.width
                        text: ({todo: "В планах", doing: "В работе", done: "Готово"})[entry.row.status] +
                              (entry.row.conflict ? " · конфликт" : entry.row.pending ? " · ожидает отправки" : "")
                        font.pixelSize: Theme.fontSizeSmall; color: palette.highlightColor; wrapMode: Text.Wrap
                    }
                    Label { width: parent.width; text: entry.row.description; visible: text.length > 0; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.Wrap }
                    Row {
                        width: parent.width; spacing: Theme.paddingMedium
                        Button {
                            width: (parent.width - Theme.paddingMedium)/2; text: "Изменить"
                            enabled: controller.authenticated && !controller.busy
                            onClicked: pageStack.push(Qt.resolvedUrl("TaskDialog.qml"), {record: entry.row})
                        }
                        Button {
                            width: (parent.width - Theme.paddingMedium)/2; text: "Удалить"
                            enabled: controller.authenticated && !controller.busy
                            onClicked: entry.remorseAction("Удаление задачи", function () { controller.remove(entry.row.id) })
                        }
                    }
                }
            }
        }
        VerticalScrollDecorator {}
    }
    Rectangle {
        id: toolbar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: actions.height + 2*Theme.paddingMedium; color: "#e8eef8"
        Row {
            id: actions
            x: Theme.paddingMedium; y: Theme.paddingMedium
            width: parent.width - 2*x; spacing: Theme.paddingSmall
            Button {
                width: (parent.width - 2*Theme.paddingSmall)/3; text: "Настройки"
                onClicked: pageStack.push(Qt.resolvedUrl("ConnectionPage.qml"))
            }
            Button {
                width: (parent.width - 2*Theme.paddingSmall)/3; text: "Обновить"
                enabled: controller.authenticated && !controller.offline && !controller.busy
                onClicked: controller.sync()
            }
            Button {
                width: (parent.width - 2*Theme.paddingSmall)/3; text: "+ Задача"
                enabled: controller.authenticated && !controller.busy
                onClicked: pageStack.push(Qt.resolvedUrl("TaskDialog.qml"))
            }
        }
    }
}
