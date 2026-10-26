import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    // Светлая палитра наследуется полями, кнопками и меню страницы.
    palette.colorScheme: Theme.DarkOnLight
    palette.highlightColor: "#1565c0"
    backgroundColor: "#f7f9fc"
    property var record: ({})
    SilicaFlickable {
        anchors.fill: parent; contentHeight: fields.height
        Column {
            id: fields; width: parent.width; spacing: Theme.paddingLarge
            PageHeader { title: record.id ? "Редактирование задачи" : "Новая задача" }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: "01 / Что нужно сделать"; color: palette.highlightColor
            }
            TextField { id: title; width: parent.width; label: "Заголовок"; text: record.title || "" }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: "02 / Срок и этап"; color: palette.highlightColor
            }
            TextField { id: dueDate; width: parent.width; label: "Срок YYYY-MM-DD"; text: record.due_date || Qt.formatDate(new Date(), "yyyy-MM-dd") }
            ComboBox {
                id: state; width: parent.width; label: "Статус"
                currentIndex: record.status === "done" ? 2 : record.status === "doing" ? 1 : 0
                menu: ContextMenu { MenuItem { text: "К выполнению" } MenuItem { text: "В работе" } MenuItem { text: "Готово" } }
            }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: "03 / Подробности"; color: palette.highlightColor
            }
            TextArea { id: description; width: parent.width; label: "Описание"; text: record.description || "" }
            Button {
                text: record.id ? "Сохранить изменения" : "Добавить в план"; anchors.horizontalCenter: parent.horizontalCenter
                enabled: !tasksController.busy && tasksController.authenticated
                onClicked: {
                    // Форма закрывается только после успешной записи в локальную SQLite.
                    if (tasksController.save(record.id || "", dueDate.text, title.text, ["todo", "doing", "done"][state.currentIndex], description.text)) pageStack.pop()
                    else error.text = tasksController.status
                }
            }
            Label { id: error; x: Theme.horizontalPageMargin; width: parent.width - 2*x; wrapMode: Text.Wrap; color: palette.highlightColor }
        }
        VerticalScrollDecorator {}
    }
}
