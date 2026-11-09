# Схемы JSON и правила валидации. Pydantic-схема — контракт JSON, не таблица БД. Типы дат/UUID и
# ограничения проверяются до изменения данных.
"""В JSON сумма передаётся в копейках; float для денег не используется."""
from datetime import date as Date
from uuid import UUID

# BaseModel задаёт JSON-схему, Field — ограничения, ConfigDict — общие правила проверки.
from pydantic import BaseModel, ConfigDict, Field


# Базовая Pydantic-схема. Правила наследуются входными моделями; FastAPI проверяет JSON до вызова
# маршрута.
class Input(BaseModel):
    # Запрещаем лишние поля и очищаем строки по краям. Опечатка ключа JSON становится ошибкой, а не молча
    # игнорируется.
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)


# Контракт входа: логин и пароль с ограничением длины. Это схема запроса, а не таблица пользователей.
class Login(Input):
    # Field уточняет длину, диапазон или default. Аннотация типа используется Pydantic до вызова
    # обработчика.
    username: str = Field(min_length=1, max_length=80)
    # Field уточняет длину, диапазон или default. Аннотация типа используется Pydantic до вызова
    # обработчика.
    password: str = Field(min_length=1, max_length=256)


# Поля расхода. Сумма — целые копейки, чтобы не получить ошибки округления денежных дробей.
class ExpenseFields(Input):
    # Календарная дата проверяется типом Date. В JSON это ISO-строка YYYY-MM-DD; время суток/часовой пояс
    # поля не требуется.
    date: Date
    # Field уточняет длину, диапазон или default. Аннотация типа используется Pydantic до вызова
    # обработчика.
    category: str = Field(min_length=1, max_length=80)
    # Field уточняет длину, диапазон или default. Аннотация типа используется Pydantic до вызова
    # обработчика.
    # Сумма в целых копейках. strict/int-ограничения, если указаны в Field, не позволяют заменить сумму
    # произвольной строкой или дробью.
    amount_minor: int = Field(strict=True, gt=0, le=1_000_000_000_00)
    # Field уточняет длину, диапазон или default. Аннотация типа используется Pydantic до вызова
    # обработчика.
    comment: str = Field(default='', max_length=2000)


# Схема создания: поля расхода плюс UUID клиента. Идентификатор можно создать ещё offline.
class ExpenseCreate(ExpenseFields):
    # UUID валидируется как тип, а при JSON-выдаче сериализуется строкой. Он нужен и для новой
    # offline-записи.
    id: UUID


# Необязательные поля PATCH. Отсутствующее поле остаётся прежним, а явно переданный null дополнительно
# проверяет маршрут.
class ExpensePatch(Input):
    # Календарная дата проверяется типом Date. В JSON это ISO-строка YYYY-MM-DD; время суток/часовой пояс
    # поля не требуется.
    date: Date | None = None
    # Field уточняет длину, диапазон или default. Аннотация типа используется Pydantic до вызова
    # обработчика.
    category: str | None = Field(default=None, min_length=1, max_length=80)
    # Field уточняет длину, диапазон или default. Аннотация типа используется Pydantic до вызова
    # обработчика.
    # Сумма в целых копейках. strict/int-ограничения, если указаны в Field, не позволяют заменить сумму
    # произвольной строкой или дробью.
    amount_minor: int | None = Field(default=None, strict=True, gt=0, le=1_000_000_000_00)
    # Field уточняет длину, диапазон или default. Аннотация типа используется Pydantic до вызова
    # обработчика.
    comment: str | None = Field(default=None, max_length=2000)
