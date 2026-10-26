import QtQuick 2.0
import Sailfish.Silica 1.0
import "services"

ApplicationWindow {
    id: app
    SystemNotification { controller: tasksController }
    initialPage: Component { MainPage {} }
    cover: Component {
        CoverBackground {
            Label { anchors.centerIn: parent; text: "Задачи ЛР3\n" + tasksController.pendingCount + " в очереди"; horizontalAlignment: Text.AlignHCenter }
        }
    }
}
