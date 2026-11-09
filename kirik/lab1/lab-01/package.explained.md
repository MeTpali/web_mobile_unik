# Пояснения к package.json

Настройки и зависимости компонента.

JSON не поддерживает комментарии. Сам файл остаётся валидным; пояснения к его полям приведены здесь.

## name

Имя npm-пакета, не заголовок экрана.

```json
"kirik-calculator"
```

## version

Версия проекта, отдельно от версии Node.js.

```json
"1.0.0"
```

## private

true запрещает случайную публикацию пакета в npm.

```json
true
```

## type

module включает import/export вместо require/module.exports.

```json
"module"
```

## engines

Допустимые версии Node.js. Другая версия может иначе выполнять зависимости.

```json
{
  "node": ">=24.13.0 <25"
}
```

## scripts

Именованные команды: start запускает сервер, test — проверки, build — браузерную сборку, dev — режим разработки.

```json
{
  "start": "node server/index.js",
  "test": "node --test"
}
```

## dependencies

Библиотеки исполнения (Express/React). npm ci устанавливает точные версии по lock-файлу.

```json
{
  "express": "5.2.1"
}
```
