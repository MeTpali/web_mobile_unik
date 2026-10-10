"""Предметная логика без зависимости от FastAPI и сетевого транспорта."""

from secrets import randbelow

LIMIT = 1_000_000_000


class InvalidRange(ValueError):
    """Неверный пользовательский диапазон; преобразуется в сообщение протокола."""


def generate(minimum: object, maximum: object) -> dict:
    """Вернуть целое число из включённого диапазона после строгой проверки."""
    # bool — подкласс int в Python, поэтому isinstance здесь недостаточно.
    if type(minimum) is not int or type(maximum) is not int:
        raise InvalidRange("min и max должны быть целыми числами")
    if not -LIMIT <= minimum <= LIMIT or not -LIMIT <= maximum <= LIMIT:
        raise InvalidRange("Границы должны быть от −1 000 000 000 до 1 000 000 000")
    if minimum > maximum:
        raise InvalidRange("Минимум не должен превышать максимум")
    # randbelow(n) возвращает 0..n-1. +1 включает верхнюю границу,
    # одинаковые границы тоже работают: randbelow(1) всегда равен нулю.
    return {"min": minimum, "max": maximum,
            "value": minimum + randbelow(maximum - minimum + 1)}
