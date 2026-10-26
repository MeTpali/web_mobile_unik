import QtQuick 2.0
import Sailfish.Silica 1.0

ApplicationWindow {
    id: app
    initialPage: Component { MainPage {} }
    cover: Component {
        CoverBackground {
            Label { anchors.centerIn: parent; text: "Задачи ЛР2\n" + tasksController.pendingCount + " в очереди"; horizontalAlignment: Text.AlignHCenter }
        }
    }
}
