import 'number_range.dart';

class RandomResult {
  const RandomResult(this.value, this.range);
  final int value;
  final NumberRange range;

  int get minimum => range.minimum;
  int get maximum => range.maximum;
}
