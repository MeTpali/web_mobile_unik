import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: dialog
    property var record: ({})
    SilicaFlickable {
        anchors.fill: parent; contentHeight: fields.height
        Column {
            id: fields; width: parent.width
            PageHeader { title: record.id ? "Редактирование" : "Новый расход" }
            TextField { id: date; width: parent.width; label: "Дата YYYY-MM-DD"; text: record.date || Qt.formatDate(new Date(), "yyyy-MM-dd") }
            TextField { id: category; width: parent.width; label: "Категория"; text: record.category || "" }
            TextField { id: amount; width: parent.width; label: "Сумма, рубли"; inputMethodHints: Qt.ImhFormattedNumbersOnly; text: record.amount_minor ? (record.amount_minor/100).toFixed(2) : "" }
            TextArea { id: comment; width: parent.width; label: "Комментарий"; text: record.comment || "" }
            Button {
                text: "Сохранить"; anchors.horizontalCenter: parent.horizontalCenter
                enabled: !expensesController.busy && expensesController.authenticated
                onClicked: {
                    // Закрываем форму только после успешной записи в локальную БД.
                    if (expensesController.save(record.id || "", date.text, category.text, amount.text, comment.text)) pageStack.pop()
                    else error.text = expensesController.status
                }
            }
            Label { id: error; x: Theme.horizontalPageMargin; width: parent.width - 2*x; wrapMode: Text.Wrap; color: Theme.highlightColor }
        }
        VerticalScrollDecorator {}
    }
}
