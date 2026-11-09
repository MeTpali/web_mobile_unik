// Компонент интерфейса или WebSocket-адаптер. QML декларативно описывает дерево. Выражения свойств —
// привязки; onClicked вызывается при действии пользователя. Theme задаёт размеры с учётом плотности
// экрана.
import QtQuick 2.0
import Sailfish.Silica 1.0

// Корневое окно Silica управляет стеком страниц и обложкой. Контроллер приходит из C++-контекста, а не
// создаётся каждым экраном.
ApplicationWindow {
    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
    id: app
    // DarkOnLight задаёт тёмный текст на светлом фоне. Локальная палитра наследуется дочерними элементами.
    palette.colorScheme: Theme.DarkOnLight
    palette.highlightColor: "#1565c0"
    initialPage: Component { MainPage {} }
    cover: Component {
        // Обложка свёрнутого приложения показывает краткое состояние без создания отдельной сессии/БД.
        CoverBackground {
            // DarkOnLight задаёт тёмный текст на светлом фоне. Локальная палитра наследуется дочерними элементами.
            palette.colorScheme: Theme.DarkOnLight
            // Декоративная область/карточка. Высота по содержимому вмещает переносы текста, цвет/скругления
            // отделяют группу полей.
            Rectangle { anchors.fill: parent; color: "#f7f9fc" }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label { anchors.centerIn: parent; text: "Задачи ЛР2\n" + tasksController.pendingCount + " в очереди"; horizontalAlignment: Text.AlignHCenter }
        }
    }
}
