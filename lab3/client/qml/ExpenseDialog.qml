// Форма создания и редактирования расхода. QML декларативно описывает дерево. Выражения свойств —
// привязки; onClicked вызывается при действии пользователя. Theme задаёт размеры с учётом плотности
// экрана.
import QtQuick 2.0
import Sailfish.Silica 1.0

// Экран стека Silica: push открывает следующую страницу, pop возвращает предыдущую. Общие данные
// остаются в контроллере.
Page {
    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
    id: dialog
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
            id: fields; width: parent.width
            // Заголовок страницы участвует в её раскладке и навигации. Это не отдельный процесс или контроллер.
            PageHeader { title: record.id ? "Редактирование" : "Новый расход" }
            // Однострочный ввод: text хранит исходное значение, enabled блокирует редактирование во время
            // операции. Окончательную проверку выполняет контроллер.
            TextField { id: date; width: parent.width; label: "Дата YYYY-MM-DD"; text: record.date || Qt.formatDate(new Date(), "yyyy-MM-dd") }
            // Однострочный ввод: text хранит исходное значение, enabled блокирует редактирование во время
            // операции. Окончательную проверку выполняет контроллер.
            TextField { id: category; width: parent.width; label: "Категория"; text: record.category || "" }
            // Однострочный ввод: text хранит исходное значение, enabled блокирует редактирование во время
            // операции. Окончательную проверку выполняет контроллер.
            TextField { id: amount; width: parent.width; label: "Сумма, рубли"; inputMethodHints: Qt.ImhFormattedNumbersOnly; text: record.amount_minor ? (record.amount_minor/100).toFixed(2) : "" }
            // Многострочное описание. Введённую строку контроллер проверит до локального сохранения.
            TextArea { id: comment; width: parent.width; label: "Комментарий"; text: record.comment || "" }
            // Кнопка вызывает onClicked при enabled. UI-блокировка помогает пользователю; контроллер дополнительно
            // защищает операцию от недопустимого вызова.
            Button {
                text: "Сохранить"; anchors.horizontalCenter: parent.horizontalCenter
                enabled: !expensesController.busy && expensesController.authenticated
                onClicked: {
                    // Закрываем форму только после успешной записи в локальную БД.
                    if (expensesController.save(record.id || "", date.text, category.text, amount.text, comment.text)) pageStack.pop()
                    else error.text = expensesController.status
                }
            }
            // Текст без редактирования. wrapMode переносит длинное имя/описание, чтобы оно не вышло за границы
            // экрана.
            Label { id: error; x: Theme.horizontalPageMargin; width: parent.width - 2*x; wrapMode: Text.Wrap; color: Theme.highlightColor }
        }
        // Штатный индикатор положения прокрутки. Не меняет модель или сохранённые данные.
        VerticalScrollDecorator {}
    }
}
