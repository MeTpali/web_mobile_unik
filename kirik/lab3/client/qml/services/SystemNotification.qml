import QtQml 2.2
import Nemo.Notifications 1.0

// Системные уведомления отделены от WSS-транспорта, контроллера и экрана.
Notification {
    id: notification
    property var controller: null
    property var seen: []
    property int publishedCount: 0
    property string lastEventId: ""
    appName: "Задачи ЛР3"
    appIcon: "ru.kirik.taskslab3"
    expireTimeout: -1
    isTransient: false

    function notifyTask(event) {
        var titles = {POST: "Задача добавлена", PATCH: "Задача изменена", DELETE: "Задача удалена"}
        if (!event || event.type !== "task.changed" || !titles[event.action]) return
        if (event.event_id && seen.indexOf(event.event_id) !== -1) return
        summary = titles[event.action]
        body = "Изменения получены с сервера. Список задач обновляется."
        previewSummary = summary
        previewBody = body
        timestamp = new Date()
        // publish сохраняет replacesId: следующие события обновляют одну запись.
        publish()
        if (replacesId) {
            lastEventId = event.event_id || ""
            if (lastEventId) {
                if (seen.length >= 128) seen.shift()
                seen.push(lastEventId)
            }
            publishedCount += 1
            console.info("System notification published: " + replacesId + " " + event.action)
        } else console.warn("Notification manager did not return an ID")
    }

    property Connections subscription: Connections {
        target: notification.controller
        onTaskChanged: notification.notifyTask(event)
    }
}
