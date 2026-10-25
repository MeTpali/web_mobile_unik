"""В JSON сумма передаётся в копейках; float для денег не используется."""
from datetime import date as Date
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class Input(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)


class Login(Input):
    username: str = Field(min_length=1, max_length=80)
    password: str = Field(min_length=1, max_length=256)


class ExpenseFields(Input):
    date: Date
    category: str = Field(min_length=1, max_length=80)
    amount_minor: int = Field(strict=True, gt=0, le=1_000_000_000_00)
    comment: str = Field(default='', max_length=2000)


class ExpenseCreate(ExpenseFields):
    id: UUID


class ExpensePatch(Input):
    date: Date | None = None
    category: str | None = Field(default=None, min_length=1, max_length=80)
    amount_minor: int | None = Field(default=None, strict=True, gt=0, le=1_000_000_000_00)
    comment: str | None = Field(default=None, max_length=2000)
