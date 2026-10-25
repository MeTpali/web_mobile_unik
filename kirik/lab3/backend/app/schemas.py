"""Контракт задачи: срок ISO, заголовок, описание и конечный набор статусов."""
from datetime import date as Date
from typing import Literal
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field

TaskStatus = Literal['todo', 'doing', 'done']

class Input(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)

class Login(Input):
    username: str = Field(min_length=1, max_length=80)
    password: str = Field(min_length=1, max_length=256)

class TaskFields(Input):
    due_date: Date
    title: str = Field(min_length=1, max_length=160)
    status: TaskStatus = 'todo'
    description: str = Field(default='', max_length=2000)

class TaskCreate(TaskFields):
    id: UUID

class TaskPatch(Input):
    due_date: Date | None = None
    title: str | None = Field(default=None, min_length=1, max_length=160)
    status: TaskStatus | None = None
    description: str | None = Field(default=None, max_length=2000)
