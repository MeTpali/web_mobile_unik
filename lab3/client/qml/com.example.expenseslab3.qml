import QtQuick 2.0
import Sailfish.Silica 1.0
import "services"

ApplicationWindow {
    id: app
    SystemNotification { controller: expensesController }
    initialPage: Component { MainPage {} }
    cover: Component {
        CoverBackground {
            Label { anchors.centerIn: parent; text: "Расходы ЛР3\n" + expensesController.pendingCount + " в очереди"; horizontalAlignment: Text.AlignHCenter }
        }
    }
}
