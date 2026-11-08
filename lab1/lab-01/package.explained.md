# Пояснения к package.json

Описывает версии React, Express и Vite, ограничение версии Node.js и команды установки, тестирования, сборки и запуска.

JSON не поддерживает комментарии. Сам файл остаётся валидным; пояснения к его полям приведены здесь.

## name

Имя npm-пакета, не заголовок экрана.

```json
"lab-01-random-generator"
```

## version

Версия проекта, отдельно от версии Node.js.

```json
"0.1.0"
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
  "dev:client": "vite",
  "dev:server": "node --watch server/index.js",
  "build": "vite build",
  "start": "node server/index.js",
  "test": "node --test"
}
```

## dependencies

Библиотеки исполнения (Express/React). npm ci устанавливает точные версии по lock-файлу.

```json
{
  "express": "5.2.1",
  "react": "19.3.0",
  "react-dom": "19.3.0"
}
```

## devDependencies

Инструменты разработки/сборки, например Vite. Готовому браузерному клиенту Vite-сервер не нужен.

```json
{
  "@vitejs/plugin-react": "6.1.1",
  "vite": "8.3.1"
}
```
