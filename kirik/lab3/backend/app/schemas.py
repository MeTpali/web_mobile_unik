# JSON-контракт задачи, срок и допустимые статусы. Pydantic-схема — контракт JSON, не таблица БД. Типы
# дат/UUID и ограничения проверяются до изменения данных.
"""Контракт задачи: срок ISO, заголовок, описание и конечный набор статусов."""
from datetime import date as Date
from typing import Literal
from uuid import UUID
# BaseModel задаёт JSON-схему, Field — ограничения, ConfigDict — общие правила проверки.
from pydantic import BaseModel, ConfigDict, Field

# Literal перечисляет единственно допустимые статусы todo/doing/done. Произвольную строку схема
# отвергнет.
TaskStatus = Literal['todo', 'doing', 'done']

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

# Контракт задачи: календарный срок, заголовок, фиксированный набор статусов и описание.
class TaskFields(Input):
    # Календарная дата проверяется типом Date. В JSON это ISO-строка YYYY-MM-DD; время суток/часовой пояс
    # поля не требуется.
    due_date: Date
    # Field уточняет длину, диапазон или default. Аннотация типа используется Pydantic до вызова
    # обработчика.
    title: str = Field(min_length=1, max_length=160)
    # Literal перечисляет единственно допустимые статусы todo/doing/done. Произвольную строку схема
    # отвергнет.
    # Допустимы только значения TaskStatus. None в PATCH означает необязательность поля на уровне схемы;
    # handler отдельно запрещает явный null.
    status: TaskStatus = 'todo'
    # Field уточняет длину, диапазон или default. Аннотация типа используется Pydantic до вызова
    # обработчика.
    description: str = Field(default='', max_length=2000)

# Схема создания задачи с UUID клиента, одинаковым до и после синхронизации.
class TaskCreate(TaskFields):
    # UUID валидируется как тип, а при JSON-выдаче сериализуется строкой. Он нужен и для новой
    # offline-записи.
    id: UUID

# Схема частичной правки: exclude_unset в маршруте отличит пропущенное поле от переданного значения.
class TaskPatch(Input):
    # Календарная дата проверяется типом Date. В JSON это ISO-строка YYYY-MM-DD; время суток/часовой пояс
    # поля не требуется.
    due_date: Date | None = None
    # Field уточняет длину, диапазон или default. Аннотация типа используется Pydantic до вызова
    # обработчика.
    title: str | None = Field(default=None, min_length=1, max_length=160)
    # Допустимы только значения TaskStatus. None в PATCH означает необязательность поля на уровне схемы;
    # handler отдельно запрещает явный null.
    status: TaskStatus | None = None
    # Field уточняет длину, диапазон или default. Аннотация типа используется Pydantic до вызова
    # обработчика.
    description: str | None = Field(default=None, max_length=2000)
