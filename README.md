# crystal-shards.online

Каталог Crystal-шардов на GitHub: краулер + высокопроизводительный сервер
без nginx и без клиентского JavaScript. Поиск — как на rubygems.org:
server-side, ранжирование по имени/топикам/описанию + звёзды.

## Архитектура

```
cron (каждые 6ч) ──> bin/crawler
                        │  GitHub API (search + raw shard.yml)
                        │  кэш по pushed_at: неизменённые репо не перекачиваются
                        ├─> data/shards.json          (снапшот, инкрементальный кэш)
                        └─> public/**/*.html          (ECR-шаблоны, sitemap.xml)

bin/server ──> public/            статика через StaticFileHandler
           ──> /search?q=         динамика: память + ECR, hot reload по mtime
```

- Ноль зависимостей от шардов: только stdlib (HTTP, JSON, YAML, ECR).
- ~10k шардов целиком в памяти (~10 МБ); поиск — линейный скоринг,
  доли миллисекунды на запрос.
- Clean URLs: `/`, `/categories`, `/category/db`, `/shards/owner/repo`.
- SEO: canonical, OpenGraph, `sitemap.xml`, `robots.txt`.

## Разработка

```sh
crystal build --release -o bin/server src/server.cr
crystal build --release -o bin/crawler src/crawler.cr

# тестовый краул (25 репо, без токена работает, но медленно)
CRAWL_LIMIT=25 CRAWL_FROM=2026-01-01 ./bin/crawler

# полный краул — нужен токен https://github.com/settings/tokens (без scopes)
GITHUB_TOKEN=ghp_... ./bin/crawler

# сервер
PORT=8080 ./bin/server
```

Переменные окружения: см. `.env.example`.

## Деплой (Capistrano)

Требования на сервере: пользователь `deploy` с sudo, Crystal, git,
systemd-юнит из `deploy/crystal-shards.service`, cron из `deploy/crontab`.

```sh
bundle install
cap production deploy       # сборка кристалла, рестарт сервиса
cap production deploy:crawl # первый краул
```

`shared/.env.production` переживает релизы (linked files), `data/` тоже.

## Категории

Назначаются автоматически: сначала по GitHub topics, затем по ключевым
словам в описании. Словарь — `src/categories.cr`, расширяется тривиально.
