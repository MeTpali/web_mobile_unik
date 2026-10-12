// Ответ генерации связывает значение с исходным диапазоном.
// Без этой связи результат старого запроса можно было бы ошибочно подписать
// новыми значениями из изменённых пользователем полей.
import 'number_range.dart';

class RandomResult {
  const RandomResult(this.value, this.range);
  final int value;
  final NumberRange range;

  // Геттеры дают UI удобный доступ к границам вложенной модели.
  int get minimum => range.minimum;
  int get maximum => range.maximum;
}
