// Модель запроса/результата не зависит от UI и транспорта.
class Calculation {
  const Calculation(this.a, this.b, this.operation, this.value);
  final double a, b, value;
  final String operation;
  factory Calculation.fromJson(Map<String, dynamic> data) {
    if (data['a'] is! num || data['b'] is! num || data['value'] is! num ||
        !['+', '-', '*', '/'].contains(data['operation'])) {
      throw const FormatException('Неверный ответ сервера');
    }
    final result = Calculation((data['a'] as num).toDouble(), (data['b'] as num).toDouble(),
        data['operation'] as String, (data['value'] as num).toDouble());
    if (![result.a, result.b, result.value].every((n) => n.isFinite)) {
      throw const FormatException('Сервер вернул бесконечное число');
    }
    return result;
  }
  @override
  String toString() => '$a $operation $b = $value';
}
