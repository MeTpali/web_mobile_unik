"""Вычисления не зависят от FastAPI: их можно тестировать без сети."""
import math

LIMIT = 1_000_000_000_000


def calculate(a, b, operation):
    # bool в Python является подклассом int, но не является операндом калькулятора.
    if type(a) not in (int, float) or type(b) not in (int, float):
        raise ValueError('Операнды должны быть числами')
    if not all(abs(x) <= LIMIT and math.isfinite(x) for x in (a, b)):
        raise ValueError('Операнды должны быть конечными числами от −10¹² до 10¹²')
    if operation not in ('+', '-', '*', '/'):
        raise ValueError('Допустимые операции: +, -, *, /')
    if operation == '/' and b == 0:
        raise ValueError('Деление на ноль запрещено')
    value = {'+': lambda: a+b, '-': lambda: a-b, '*': lambda: a*b, '/': lambda: a/b}[operation]()
    if not math.isfinite(value):
        raise ValueError('Результат не является конечным числом')
    return {'a': a, 'b': b, 'operation': operation, 'value': value}
