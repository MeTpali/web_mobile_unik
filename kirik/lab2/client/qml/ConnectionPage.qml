import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    palette.colorScheme: Theme.DarkOnLight
    palette.highlightColor: "#1565c0"
    backgroundColor: "#f7f9fc"
    property var controller: tasksController
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge
        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingMedium
            PageHeader { title: "Подключение" }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: "Учётная запись и синхронизация"; wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeLarge
            }
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
                text: controller.status; wrapMode: Text.Wrap; color: palette.highlightColor
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

        }
        VerticalScrollDecorator {}
    }
}
