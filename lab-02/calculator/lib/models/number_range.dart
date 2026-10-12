// Модель и правила диапазона не зависят от Flutter или сетевого транспорта.
// final запрещает менять границы после создания объекта.
class NumberRange {
  const NumberRange(this.minimum, this.maximum);

  static const limit = 1000000000;
  final int minimum;
  final int maximum;

  // Геттер вычисляет признак корректности по обеим границам.
  // Проверка нужна и при вызове контроллера напрямую, в обход формы.
  bool get isValid =>
      minimum.abs() <= limit && maximum.abs() <= limit && minimum <= maximum;

  // Формат валидатора Flutter: null означает успех, строка — текст ошибки.
  // tryParse не выбрасывает исключение для пустого текста или дроби.
  static String? validateBound(String? text) {
    final value = int.tryParse(text?.trim() ?? '');
    if (value == null) return 'Введите целое число';
    if (value.abs() > limit) return 'От −1 млрд до 1 млрд';
    return null;
  }

  // Сначала проверяем число, затем порядок относительно минимума.
  // Проверка минимального поля выполняется его собственным валидатором.
  static String? validateMaximum(String? text, String minimumText) {
    final error = validateBound(text);
    if (error != null) return error;
    final minimum = int.tryParse(minimumText.trim());
    if (minimum != null && int.parse(text!.trim()) < minimum) {
      return 'Максимум должен быть не меньше минимума';
    }
    return null;
  }
}
