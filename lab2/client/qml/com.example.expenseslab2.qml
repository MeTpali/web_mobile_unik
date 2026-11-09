// Корневое окно приложения и обложка. QML декларативно описывает дерево. Выражения свойств — привязки;
// onClicked вызывается при действии пользователя. Theme задаёт размеры с учётом плотности экрана.
import QtQuick 2.0
import Sailfish.Silica 1.0

// Корневое окно Silica управляет стеком страниц и обложкой. Контроллер приходит из C++-контекста, а не
// создаётся каждым экраном.
ApplicationWindow {
    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
    id: app
    initialPage: Component { MainPage {} }
    cover: Component {
        // Обложка свёрнутого приложения показывает краткое состояние без создания отдельной сессии/БД.
        CoverBackground {
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label { anchors.centerIn: parent; text: "Расходы ЛР2\n" + expensesController.pendingCount + " в очереди"; horizontalAlignment: Text.AlignHCenter }
        }
    }
}
