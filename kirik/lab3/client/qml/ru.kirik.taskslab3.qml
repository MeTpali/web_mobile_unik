import QtQuick 2.0
import Sailfish.Silica 1.0
import "services"

ApplicationWindow {
    id: app
    palette.colorScheme: Theme.DarkOnLight
    palette.highlightColor: "#1565c0"
    SystemNotification { controller: tasksController }
    initialPage: Component { MainPage {} }
    cover: Component {
        CoverBackground {
            palette.colorScheme: Theme.DarkOnLight
            Rectangle { anchors.fill: parent; color: "#f7f9fc" }
            Label { anchors.centerIn: parent; text: "Задачи ЛР3\n" + tasksController.pendingCount + " в очереди"; horizontalAlignment: Text.AlignHCenter }
        }
    }
}
