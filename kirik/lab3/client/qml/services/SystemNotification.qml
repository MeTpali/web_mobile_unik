// Штатные уведомления ОС по task.changed, защита от повторов и замена предыдущей записи. Адаптер
// системного диспетчера, а не сетевой транспорт. Получает доменное событие, фильтрует дубликаты и
// публикует запись. Процесс приложения должен исполняться.
import QtQml 2.2
import Nemo.Notifications 1.0

// Системные уведомления отделены от WSS-транспорта, контроллера и экрана.
// Публикует запись системному диспетчеру. Баннер рисует ОС, а не страница приложения.
Notification {
    // id — локальное имя QML-объекта для привязок/обработчиков; это не UUID записи сервера.
    id: notification
    // Ссылка на общий контроллер, а не новая копия сессии или SQLite для этой страницы.
    property var controller: null
    property var seen: []
    property int publishedCount: 0
    property string lastEventId: ""
    appName: "Задачи ЛР3"
    appIcon: "ru.kirik.taskslab3"
    // Время жизни записи задаётся системному диспетчеру; отрицательное значение оставляет управление
    // сроком ОС.
    expireTimeout: -1
    // Непреходящее уведомление может сохраняться в центре уведомлений, а не исчезать сразу после баннера.
    isTransient: false

    // Выбираем уведомление по доменному событию. Дубликаты event_id и heartbeat не должны создавать
    // записи.
    function notifyTask(event) {
        var titles = {POST: "Задача добавлена", PATCH: "Задача изменена", DELETE: "Задача удалена"}
        if (!event || event.type !== "task.changed" || !titles[event.action]) return
        // Отбрасываем уже обработанный event_id: сетевой повтор не должен создать повторное уведомление.
        if (event.event_id && seen.indexOf(event.event_id) !== -1) return
        summary = titles[event.action]
        body = "Изменения получены с сервера. Список задач обновляется."
        // Краткий текст для системного preview/баннера. Реальную видимость определяют настройки и политика ОС.
        previewSummary = summary
        // Краткий текст для системного preview/баннера. Реальную видимость определяют настройки и политика ОС.
        previewBody = body
        timestamp = new Date()
        // publish сохраняет replacesId: следующие события обновляют одну запись.
        // Публикуем системную запись. replacesId используется для обновления одной записи следующими
        // событиями.
        publish()
        // Ненулевой системный ID подтверждает публикацию. Только после успеха отмечаем event_id как
        // показанный.
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

    // Notification не имеет default property для свободного Connections, поэтому подписка объявлена
    // свойством.
    property Connections subscription: Connections {
        target: notification.controller
        onTaskChanged: notification.notifyTask(event)
    }
}
