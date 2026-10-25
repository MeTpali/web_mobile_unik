import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    property var record: ({})
    SilicaFlickable {
        anchors.fill: parent; contentHeight: fields.height
        Column {
            id: fields; width: parent.width; spacing: Theme.paddingMedium
            PageHeader { title: record.id ? "Редактирование задачи" : "Новая задача" }
            TextField { id: title; width: parent.width; label: "Заголовок"; text: record.title || "" }
            TextField { id: dueDate; width: parent.width; label: "Срок YYYY-MM-DD"; text: record.due_date || Qt.formatDate(new Date(), "yyyy-MM-dd") }
            ComboBox {
                id: state; width: parent.width; label: "Статус"
                currentIndex: record.status === "done" ? 2 : record.status === "doing" ? 1 : 0
                menu: ContextMenu { MenuItem { text: "К выполнению" } MenuItem { text: "В работе" } MenuItem { text: "Готово" } }
            }
            TextArea { id: description; width: parent.width; label: "Описание"; text: record.description || "" }
            Button {
                text: "Сохранить"; anchors.horizontalCenter: parent.horizontalCenter
                enabled: !tasksController.busy && tasksController.authenticated
                onClicked: {
                    // Форма закрывается только после успешной записи в локальную SQLite.
                    if (tasksController.save(record.id || "", dueDate.text, title.text, ["todo", "doing", "done"][state.currentIndex], description.text)) pageStack.pop()
                    else error.text = tasksController.status
                }
            }
            Label { id: error; x: Theme.horizontalPageMargin; width: parent.width - 2*x; wrapMode: Text.Wrap; color: Theme.highlightColor }
        }
        VerticalScrollDecorator {}
    }
}
