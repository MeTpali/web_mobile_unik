// Создание и редактирование заголовка, срока, статуса и описания. QML декларативно описывает дерево.
// Выражения свойств — привязки; onClicked вызывается при действии пользователя. Theme задаёт размеры с
// учётом плотности экрана.
import QtQuick 2.0
import Sailfish.Silica 1.0

// Экран стека Silica: push открывает следующую страницу, pop возвращает предыдущую. Общие данные
// остаются в контроллере.
Page {
    // Светлая палитра наследуется полями, кнопками и меню страницы.
    // DarkOnLight задаёт тёмный текст на светлом фоне. Локальная палитра наследуется дочерними элементами.
    palette.colorScheme: Theme.DarkOnLight
    palette.highlightColor: "#1565c0"
    backgroundColor: "#f7f9fc"
    // Параметр формы: пустой объект означает создание, объект с id — правку существующей записи.
    property var record: ({})
    // Прокручиваемая форма: contentHeight должен охватывать поля целиком, иначе нижние элементы окажутся
    // недоступны.
    SilicaFlickable {
        // Высота связана с фактическим содержимым и отступами: перенос текста не должен обрезать нижние
        // элементы.
        anchors.fill: parent; contentHeight: fields.height
        // Вертикальная раскладка: элементы идут сверху вниз, spacing задаёт промежуток. Высота зависит от
        // дочернего содержимого.
        Column {
            id: fields; width: parent.width; spacing: Theme.paddingLarge
            // Заголовок страницы участвует в её раскладке и навигации. Это не отдельный процесс или контроллер.
            PageHeader { title: record.id ? "Редактирование задачи" : "Новая задача" }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: "01 / Что нужно сделать"; color: palette.highlightColor
            }
            // Однострочный ввод: text хранит исходное значение, enabled блокирует редактирование во время
            // операции. Окончательную проверку выполняет контроллер.
            TextField { id: title; width: parent.width; label: "Заголовок"; text: record.title || "" }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: "02 / Срок и этап"; color: palette.highlightColor
            }
            // Однострочный ввод: text хранит исходное значение, enabled блокирует редактирование во время
            // операции. Окончательную проверку выполняет контроллер.
            TextField { id: dueDate; width: parent.width; label: "Срок YYYY-MM-DD"; text: record.due_date || Qt.formatDate(new Date(), "yyyy-MM-dd") }
            // Выбор из фиксированного списка. currentIndex сопоставляется с доменным статусом, а на сервер
            // отправляется значение, не русский перевод.
            ComboBox {
                id: state; width: parent.width; label: "Статус"
                // Индекс пункта сопоставляется с доменными значениями. Важно сохранить одинаковый порядок массива и
                // MenuItem.
                currentIndex: record.status === "done" ? 2 : record.status === "doing" ? 1 : 0
                menu: ContextMenu { MenuItem { text: "К выполнению" } MenuItem { text: "В работе" } MenuItem { text: "Готово" } }
            }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: "03 / Подробности"; color: palette.highlightColor
            }
            // Многострочное описание. Введённую строку контроллер проверит до локального сохранения.
            TextArea { id: description; width: parent.width; label: "Описание"; text: record.description || "" }
            // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
            // защищает операцию от недопустимого вызова.
            Button {
                text: record.id ? "Сохранить изменения" : "Добавить в план"; anchors.horizontalCenter: parent.horizontalCenter
                enabled: !tasksController.busy && tasksController.authenticated
                onClicked: {
                    // Форма закрывается только после успешной записи в локальную SQLite.
                    if (tasksController.save(record.id || "", dueDate.text, title.text, ["todo", "doing", "done"][state.currentIndex], description.text)) pageStack.pop()
                    else error.text = tasksController.status
                }
            }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label { id: error; x: Theme.horizontalPageMargin; width: parent.width - 2*x; wrapMode: Text.Wrap; color: palette.highlightColor }
        }
        // Штатный индикатор положения прокрутки. Не меняет модель или сохранённые данные.
        VerticalScrollDecorator {}
    }
}
