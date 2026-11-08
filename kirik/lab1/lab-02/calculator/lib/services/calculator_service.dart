// WebSocket-транспорт Flutter и обработка JSON-кадров. Сервис управляет WebSocket и JSON. Stream
// доставляет события, Future завершает асинхронный шаг; виджетам не нужно знать устройство транспорта.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Контроллер знает интерфейс сервиса; тест может подставить реализацию без сети.
abstract class CalculatorService {
  Stream<Map<String, dynamic>> get messages;
  // Асинхронное подключение с тайм-аутом. Поколение запроса отличает текущую попытку от позднего
  // завершения старой.
  Future<void> connect(Uri uri);
  // Кодирует и отправляет команду по открытому сокету. Ввод проверяет контроллер, а не транспорт.
  void send(Map<String, dynamic> request);
  // Закрывает сокет/подписку и делает старые callbacks устаревшими. unawaited помечает намеренное
  // завершение в фоне.
  void disconnect();
  // Освобождает подписки, таймеры и контроллеры ввода: закрытый экран не должен получать события и
  // удерживать ресурсы.
  void dispose();
}

class WebSocketCalculatorService implements CalculatorService {
  // Канал событий сервиса; broadcast разрешает нескольких слушателей. Канал закрывается при dispose.
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  // Текущее WebSocket-соединение; null обозначает отсутствие транспорта.
  WebSocket? _socket;
  // Сохраняем подписку, чтобы отменить её при закрытии и не получать события после уничтожения экрана.
  // Подписка на поток кадров. Сохраняется для отмены при disconnect/dispose.
  StreamSubscription<dynamic>? _subscription;
  // Счётчик поколений соединения. Увеличение делает callbacks прежнего подключения неактуальными.
  int _generation = 0;
  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  Stream<Map<String, dynamic>> get messages => _events.stream;
  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  // Асинхронное подключение с тайм-аутом. Поколение запроса отличает текущую попытку от позднего
  // завершения старой.
  Future<void> connect(Uri uri) async {
    disconnect();
    final generation = _generation;
    // await ждёт рукопожатие, не блокируя GUI. timeout не позволяет оставаться в connecting бесконечно.
    final socket = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Не удалось подключиться'));
    // Проверяем поколение подключения: прежняя попытка может завершиться позже новой, но не должна менять
    // её состояние.
    if (generation != _generation) { unawaited(socket.close()); return; }
    _socket = socket;
    _subscription = socket.listen((dynamic frame) {
      try {
        if (frame is! String) throw const FormatException('Ожидается текстовый JSON');
        // Разбираем JSON-кадр; типы/обязательные поля проверяются перед использованием.
        _events.add(jsonDecode(frame) as Map<String, dynamic>);
      } catch (error) { _events.addError(error); }
    }, onError: (Object error) => _events.addError(error),
      // Проверяем поколение подключения: прежняя попытка может завершиться позже новой, но не должна менять
      // её состояние.
      onDone: () { if (generation == _generation) _events.addError(StateError('Соединение закрыто')); });
  }
  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  // Кодирует и отправляет команду по открытому сокету. Ввод проверяет контроллер, а не транспорт.
  void send(Map<String, dynamic> request) {
    if (_socket == null) throw StateError('Нет соединения');
    // Кодируем данные в JSON-текст транспорта. Сериализация не заменяет проверку доменных значений.
    _socket!.add(jsonEncode(request));
  }
  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  // Закрывает сокет/подписку и делает старые callbacks устаревшими. unawaited помечает намеренное
  // завершение в фоне.
  void disconnect() {
    // Смена поколения сразу делает callbacks старого подключения устаревшими, даже если cancel/close ещё
    // завершаются в фоне.
    ++_generation;
    unawaited(_subscription?.cancel()); _subscription = null;
    unawaited(_socket?.close()); _socket = null;
  }
  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  // Освобождает подписки, таймеры и контроллеры ввода: закрытый экран не должен получать события и
  // удерживать ресурсы.
  void dispose() { disconnect(); unawaited(_events.close()); }
}
