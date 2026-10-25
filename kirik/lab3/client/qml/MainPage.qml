import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All
    property var controller: tasksController
    SilicaListView {
        id: list
        anchors.fill: parent
        model: controller.tasks
        PullDownMenu {
            MenuItem { text: "Новая задача"; enabled: !controller.busy && controller.authenticated; onClicked: pageStack.push(Qt.resolvedUrl("TaskDialog.qml")) }
            MenuItem { text: "Синхронизировать"; enabled: !controller.busy && controller.authenticated && !controller.offline; onClicked: controller.sync() }
        }
        header: Column {
            width: list.width
            PageHeader { title: "Задачи · ЛР3"; description: "Лабораторная 3 · HTTPS / WSS" }
            SectionHeader { text: "Сервер и вход" }
            TextField { id: server; width: parent.width; label: "HTTPS-адрес ПК"; text: controller.serverUrl; enabled: !controller.busy; inputMethodHints: Qt.ImhUrlCharactersOnly }
            TextField { id: user; width: parent.width; label: "Пользователь"; text: controller.username; enabled: !controller.busy }
            PasswordField { id: password; width: parent.width; label: "Пароль"; enabled: !controller.busy }
            TextField { id: cert; width: parent.width; label: "Путь к доверенному сертификату"; text: controller.certificatePath; enabled: !controller.busy }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Войти"; enabled: !controller.busy && !controller.offline
                onClicked: { controller.login(server.text, user.text, password.text, cert.text); password.text = "" }
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Выйти"; enabled: !controller.busy && controller.authenticated
                onClicked: controller.logout()
            }
            TextSwitch { text: "Работать offline"; description: "Не отправлять запросы, сохранять изменения на телефоне"; checked: controller.offline; enabled: !controller.busy; onClicked: controller.offline = checked }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: controller.status; wrapMode: Text.Wrap; color: Theme.highlightColor
            }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: controller.pushStatus + "\nREST: " + controller.backend
                wrapMode: Text.Wrap; font.pixelSize: Theme.fontSizeSmall
            }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                visible: controller.pushCount > 0
                text: "Push-событий: " + controller.pushCount + " · " + controller.lastPush
                wrapMode: Text.Wrap; color: Theme.highlightColor
            }
            BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; size: BusyIndicatorSize.Medium; running: controller.busy; visible: running }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: "Изменений в очереди: " + controller.pendingCount; wrapMode: Text.Wrap
            }
            Column {
                width: parent.width
                visible: !!controller.conflictInfo.server
                SectionHeader { text: "Конфликт изменений" }
                Label {
                    x: Theme.horizontalPageMargin; width: parent.width - 2*x; wrapMode: Text.Wrap
                    text: {
                        var info = controller.conflictInfo
                        if (!info.server) return ""
                        var s = info.server, l = info.payload
                        return "Локально: " + l.due_date + " · " + l.title + " · " + l.status + " · " + l.description + (info.kind === "DELETE" ? " (удаление)" : "") +
                                "\nНа сервере: " + s.due_date + " · " + s.title + " · " + s.status + " · " + s.description + (s.deleted ? " (удалено)" : "")
                    }
                }
                Button { text: "Принять серверную"; anchors.horizontalCenter: parent.horizontalCenter; enabled: !controller.busy; onClicked: controller.resolve(false) }
                Button { text: "Сохранить локальную"; anchors.horizontalCenter: parent.horizontalCenter; enabled: !controller.busy; onClicked: controller.resolve(true) }
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter; text: "Новая задача"
                enabled: !controller.busy && controller.authenticated
                onClicked: pageStack.push(Qt.resolvedUrl("TaskDialog.qml"))
            }
            SectionHeader { text: "Сохранённые задачи" }
            Label { x: Theme.horizontalPageMargin; text: "Пока нет задач"; visible: list.count === 0 }
        }
        delegate: ListItem {
            id: entry
            property var row: modelData
            contentHeight: details.height + 2*Theme.paddingMedium
            enabled: !controller.busy && controller.authenticated
            onClicked: pageStack.push(Qt.resolvedUrl("TaskDialog.qml"), {record: row})
            menu: ContextMenu {
                MenuItem { text: "Редактировать"; onClicked: pageStack.push(Qt.resolvedUrl("TaskDialog.qml"), {record: entry.row}) }
                MenuItem { text: "Удалить"; onClicked: entry.remorseAction("Удаление", function () { controller.remove(entry.row.id) }) }
            }
            Column {
                id: details; x: Theme.horizontalPageMargin; width: parent.width - 2*x; y: Theme.paddingMedium
                Label { width: parent.width; text: row.due_date + " · " + row.title; wrapMode: Text.Wrap; color: Theme.highlightColor }
                Label { width: parent.width; text: ({todo: "К выполнению", doing: "В работе", done: "Готово"})[row.status] + (row.conflict ? " · конфликт" : row.pending ? " · не отправлено" : ""); wrapMode: Text.Wrap }
                Label { width: parent.width; text: row.description; visible: text.length > 0; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.Wrap }
            }
        }
        VerticalScrollDecorator {}
    }
}
