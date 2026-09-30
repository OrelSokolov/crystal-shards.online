# Category assignment: GitHub topics take priority, then keywords
# matched against the shard description. First hit in CATEGORY_ORDER wins.

CATEGORY_ORDER = %w[
  web-frameworks database drivers networking cli gui graphics crypto
  testing algorithms concurrency system dev-tools web text science audio
  game-dev misc
]

CATEGORY_TITLES = {
  "web-frameworks" => "Web Frameworks",
  "database"       => "Databases & ORM",
  "drivers"        => "Database Drivers",
  "networking"     => "Networking & Protocols",
  "cli"            => "CLI & Terminal",
  "gui"            => "GUI & UI",
  "graphics"       => "Graphics & Imaging",
  "crypto"         => "Crypto & Security",
  "testing"        => "Testing",
  "algorithms"     => "Algorithms & Data Structures",
  "concurrency"    => "Concurrency & Async",
  "system"         => "System & FFI",
  "dev-tools"      => "Developer Tools",
  "web"            => "Web Utilities",
  "text"           => "Text & Parsing",
  "science"        => "Science & Math",
  "audio"          => "Audio & Video",
  "game-dev"       => "Game Development",
  "misc"           => "Miscellaneous",
}

CATEGORY_KEYWORDS = {
  "web-frameworks" => {"web-framework", "web-frameworks", "framework", "kemal", "lucky", "amber", "marten", "grip", "athena", "spider-gazelle", "router", "sinatra", "rails"},
  "database"       => {"database", "orm", "migration", "repository-pattern", "activerecord", "query-builder"},
  "drivers"        => {"postgres", "postgresql", "mysql", "sqlite", "sqlite3", "redis", "mongodb", "mongo", "clickhouse", "influxdb", "db", "odbc", "elasticsearch", "meilisearch"},
  "networking"     => {"networking", "network", "http-client", "websocket", "websockets", "tcp", "udp", "socket", "dns", "tls", "ssl", "email", "smtp", "imap", "ftp", "ssh", "mqtt", "amqp", "grpc", "http-server", "proxy", "vpn", "torrent", "ip-address"},
  "cli"            => {"cli", "command-line", "commandline", "terminal", "tui", "console", "option-parser", "argument-parser", "shell", "readline", "prompt"},
  "gui"            => {"gui", "ui", "imgui", "qt", "gtk", "sdl", "raylib", "windowing", "widget", "font", "freetype", "egui"},
  "graphics"       => {"graphics", "opengl", "vulkan", "image", "image-processing", "png", "jpeg", "jpg", "svg", "gif", "canvas", "rasterizer", "rendering", "vnc", "color", "chart"},
  "crypto"         => {"crypto", "cryptography", "encryption", "hash", "jwt", "oauth", "security", "password", "signature", "certificate", "totp", "random"},
  "testing"        => {"testing", "test", "tests", "spec", "mock", "mocking", "stub", "assertions", "bdd", "tdd", "coverage", "webdriver", "selenium", "benchmark", "webmock"},
  "algorithms"     => {"algorithm", "algorithms", "data-structure", "data-structures", "sorting", "graph", "tree", "trie", "string-algorithms"},
  "concurrency"    => {"concurrency", "async", "await", "actor", "pool", "scheduler", "fiber", "fibers", "parallel", "coroutine", "reactor", "queue"},
  "system"         => {"system", "filesystem", "file", "process", "os", "linux", "daemon", "cron", "logging", "logger", "compression", "archive", "ffi", "bindings", "hardware", "serial", "usb", "kernel"},
  "dev-tools"      => {"linter", "formatter", "code-generation", "codegen", "debugger", "build-tool", "documentation", "static-analysis", "ide", "language-server", "prism", "parser", "lexer", "ast", "compiler"},
  "web"            => {"html", "css", "xml", "template", "serializer", "serialization", "json", "yaml", "csv", "toml", "middleware", "session", "authentication", "authorization", "api", "rest", "graphql", "scraping", "crawler", "spider", "sitemap", "rss", "url"},
  "text"           => {"markdown", "text", "text-processing", "i18n", "unicode", "regex", "regexp", "diff", "highlighting", "syntax-highlighting", "translation", "slug", "pagination"},
  "science"        => {"math", "mathematics", "numeric", "statistics", "machine-learning", "neural-network", "deep-learning", "physics", "simulation", "linear-algebra", "matrix", "geometry", "plotting", "units", "scientific"},
  "audio"          => {"audio", "sound", "music", "video", "mp3", "wav", "ogg", "opus", "streaming", "media", "playback"},
  "game-dev"       => {"game", "gamedev", "game-development", "game-engine", "games", "sprite", "tilemap", "physics-engine", "godot"},
  "misc"           => [] of String,
}

def category_for(topics : Array(String), description : String) : String
  ltopics = topics.map(&.downcase)
  ldesc = description.downcase

  CATEGORY_ORDER.each do |cat|
    kws = CATEGORY_KEYWORDS[cat]? || next
    kws.each do |kw|
      return cat if ltopics.includes?(kw)
    end
  end

  CATEGORY_ORDER.each do |cat|
    kws = CATEGORY_KEYWORDS[cat]? || next
    kws.each do |kw|
      return cat if ldesc.includes?(kw)
    end
  end

  "misc"
end

def category_title(slug : String) : String
  CATEGORY_TITLES[slug]? || slug.titleize
end
