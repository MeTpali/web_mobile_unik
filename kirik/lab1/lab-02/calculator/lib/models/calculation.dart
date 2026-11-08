// Модель или интерфейс Flutter. Модель типизирует данные и преобразование JSON/ввода. Остальной код
// работает с проверенными полями вместо произвольной карты.
// Модель запроса/результата не зависит от UI и транспорта.
class Calculation {
  const Calculation(this.a, this.b, this.operation, this.value);
  final double a, b, value;
  final String operation;
  // Именованный фабричный конструктор получает непроверенный JSON и возвращает типизированный результат
  // только после проверок.
  factory Calculation.fromJson(Map<String, dynamic> data) {
    // Проверяем числовые типы полей и знак операции. Наличие ключа само по себе не гарантирует допустимое
    // значение.
    if (data['a'] is! num || data['b'] is! num || data['value'] is! num ||
        !['+', '-', '*', '/'].contains(data['operation'])) {
      throw const FormatException('Неверный ответ сервера');
    }
    // JSON может декодировать целое как int, дробь как double. Общий num преобразуется в единый double
    // после проверки типа.
    final result = Calculation((data['a'] as num).toDouble(), (data['b'] as num).toDouble(),
        data['operation'] as String, (data['value'] as num).toDouble());
    // И a, и b, и value должны быть конечными; NaN/Infinity не принимаются даже в синтаксически верном
    // ответе.
    if (![result.a, result.b, result.value].every((n) => n.isFinite)) {
      throw const FormatException('Сервер вернул бесконечное число');
    }
    return result;
  }
  // Реализуем метод родителя/интерфейса. Анализатор проверяет совпадение имени и сигнатуры.
  @override
  String toString() => '$a $operation $b = $value';
}
