# Crawls GitHub for Crystal repositories with a shard.yml, then writes
# data/shards.json and pre-generates static pages into public/.
#
# Run from cron. Env:
#   GITHUB_TOKEN     — strongly recommended (5000 req/h vs 60 unauthenticated)
#   CRAWL_LIMIT      — cap on repos processed (for testing)
#   CRAWL_CONCURRENCY— raw shard.yml fetch workers (default 8)

require "http/client"
require "json"
require "yaml"
require "file_utils"
require "./models"
require "./categories"
require "./render"

module Crawler
  GH_API = "https://api.github.com"
  RAW    = "https://raw.githubusercontent.com"

  class Error < Exception; end

  class Github
    def initialize(@token : String?)
    end

    def headers
      h = HTTP::Headers{
        "User-Agent" => "crystal-shards-crawler",
        "Accept"     => "application/vnd.github+json",
      }
      h["Authorization"] = "Bearer #{@token}" if @token
      h
    end

    def get(path : String) : HTTP::Client::Response
      loop do
        resp = HTTP::Client.get("#{GH_API}#{path}", headers)
        case resp.status_code
        when 200
          check_rate(resp); return resp
        when 403, 429
          check_rate(resp) # sleeps until reset when exhausted
        when 404
          return resp
        else
          raise Error.new("GET #{path} -> #{resp.status_code}: #{resp.body[0, 200]}")
        end
      end
    end

    private def check_rate(resp)
      remaining = resp.headers["X-RateLimit-Remaining"]?
      reset = resp.headers["X-RateLimit-Reset"]?
      return unless remaining == "0" && reset
      wait = reset.to_i - Time.utc.to_unix + 2
      if wait > 0
        STDERR.puts "rate limit hit, sleeping #{wait}s until reset"
        sleep wait.seconds
      end
    end
  end

  def self.run
    token = ENV["GITHUB_TOKEN"]?
    limit = ENV["CRAWL_LIMIT"]?.try &.to_i? || Int32::MAX
    concurrency = ENV["CRAWL_CONCURRENCY"]?.try &.to_i? || 8
    data_dir = ENV.fetch("DATA_DIR", "data")
    public_dir = ENV.fetch("PUBLIC_DIR", "public")

    gh = Github.new(token)
    old = SiteData.load("#{data_dir}/shards.json")
    cache = old.shards.index_by &.full_name
    STDERR.puts "cache: #{cache.size} shards from previous run"

    repos = collect_repos(gh, limit)
    STDERR.puts "discovered #{repos.size} non-fork Crystal repos"

    shards = crawl_details(gh, repos, cache, concurrency)
    STDERR.puts "#{shards.size} shards with shard.yml"

    shards.sort_by! { |s| -s.stars }
    site = SiteData.new(Time.utc.to_rfc3339, shards)

    Dir.mkdir_p(data_dir)
    File.write("#{data_dir}/shards.json", site.to_json)

    generate_site(site, public_dir)
    STDERR.puts "site generated into #{public_dir}/"
  end

  # GitHub search caps results at 1000 per query, so enumerate by
  # creation-date windows, splitting any window that overflows.
  # CRAWL_FROM bounds the range (handy for quick test crawls).
  def self.collect_repos(gh : Github, limit : Int32) : Array(JSON::Any)
    acc = Hash(String, JSON::Any).new
    from = Time.parse(ENV.fetch("CRAWL_FROM", "2008-01-01"), "%Y-%m-%d", Time::Location::UTC)
    collect_range(gh, from, Time.utc, acc, limit)
    acc.values
  end

  private def self.collect_range(gh, from : Time, to : Time,
                                 acc : Hash(String, JSON::Any), limit : Int32)
    return if acc.size >= limit

    q = "language:crystal+fork:false+created:#{from.to_s("%Y-%m-%d")}..#{to.to_s("%Y-%m-%d")}"
    first = JSON.parse(gh.get("/search/repositories?q=#{q}&sort=stars&order=desc&per_page=100&page=1").body)
    total = first["total_count"].as_i

    if total > 1000 && (to - from).total_seconds > 86400
      mid = from + Time::Span.new(seconds: ((to - from).total_seconds / 2).to_i)
      collect_range(gh, from, mid, acc, limit)
      collect_range(gh, mid, to, acc, limit)
      return
    end

    (first["items"].as_a + paginate(gh, q, total)).each do |item|
      next if item["fork"].as_bool? == true
      acc[item["full_name"].as_s] = item
      return if acc.size >= limit
    end
  end

  private def self.paginate(gh, q : String, total : Int32) : Array(JSON::Any)
    items = Array(JSON::Any).new
    pages = {(total / 100).ceil.to_i, 10}.min # search allows at most 10 pages
    (2..pages).each do |page|
      body = gh.get("/search/repositories?q=#{q}&sort=stars&order=desc&per_page=100&page=#{page}").body
      items.concat(JSON.parse(body)["items"].as_a)
    end
    items
  end

  # For every repo: reuse the cached record when pushed_at is unchanged,
  # otherwise refetch shard.yml. Repos without shard.yml are dropped.
  def self.crawl_details(gh : Github, repos : Array(JSON::Any),
                         cache : Hash(String, Shard), concurrency : Int32) : Array(Shard)
    jobs = Channel(JSON::Any).new(repos.size)
    results = Channel(Shard?).new

    repos.each { |item| jobs.send(item) }
    jobs.close

    concurrency.times do
      spawn do
        while item = jobs.receive?
          results.send(process_repo(gh, item, cache))
        end
      end
    end

    shards = [] of Shard
    repos.size.times do
      if s = results.receive
        shards << s
      end
    end
    shards
  end

  private def self.process_repo(gh : Github, item : JSON::Any, cache : Hash(String, Shard)) : Shard?
    full_name = item["full_name"].as_s
    pushed_at = item["pushed_at"].as_s

    if cached = cache[full_name]?
      return cached if cached.pushed_at == pushed_at
    end

    raw = fetch_shard_yml(full_name)
    return nil unless raw

    meta = parse_shard_yml(raw)
    build_shard(item, full_name, meta)
  rescue ex
    STDERR.puts "skip #{full_name}: #{ex.message}"
    nil
  end

  def self.fetch_shard_yml(full_name : String) : String?
    resp = HTTP::Client.get("#{RAW}/#{full_name}/HEAD/shard.yml")
    resp.status_code == 200 ? resp.body : nil
  end

  def self.parse_shard_yml(raw : String)
    doc = YAML.parse(raw)
    str = ->(k : String) { (doc[k]?).try &.as_s? || "" }
    desc = doc["description"]?
    description = if d = desc
                    d.as_s? || d.as_a?.try(&.join(" ")) || ""
                  else
                    ""
                  end
    authors = doc["authors"]?.try do |a|
      a.as_a?.try(&.map { |x| x.as_s? || "" }.reject(&.empty?).join(", ")) || ""
    end || ""
    {str.call("name"), str.call("version"), description, str.call("license"), authors}
  rescue
    {"", "", "", "", ""}
  end

  def self.build_shard(item : JSON::Any, full_name : String, meta) : Shard
    name, version, description, license, authors = meta
    Shard.new(
      full_name: full_name,
      name: name.empty? ? full_name.split('/')[1] : name,
      description: description.empty? ? (item["description"].as_s? || "") : description,
      homepage: item["homepage"].as_s? || "",
      version: version,
      license: license,
      authors: authors,
      stars: item["stargazers_count"].as_i,
      forks: item["forks_count"].as_i,
      issues: item["open_issues_count"].as_i,
      html_url: item["html_url"].as_s,
      pushed_at: item["pushed_at"].as_s,
      archived: item["archived"].as_bool? || false,
      topics: item["topics"].as_a?.try(&.map &.as_s) || [] of String,
    ).tap { |s| s.category = category_for(s.topics, s.description) }
  end

  def self.generate_site(site : SiteData, public_dir : String)
    # Wipe previously generated output so stale shard pages don't linger.
    {"shards", "category", "categories"}.each do |dir|
      FileUtils.rm_rf(File.join(public_dir, dir))
    end

    write = ->(path : String, content : String) do
      full = File.join(public_dir, path)
      Dir.mkdir_p(File.dirname(full))
      File.write(full, content)
    end

    write.call("index.html", Render.index(site))
    write.call("categories/index.html", Render.categories(site))

    Render.category_counts(site.shards).each do |(slug, _)|
      shards = site.shards.select(&.category.==(slug))
      write.call("category/#{slug}/index.html", Render.category(slug, shards))
    end

    site.shards.each do |s|
      write.call("shards/#{s.full_name}.html", Render.shard_page(s, site.shards))
    end

    write.call("sitemap.xml", Render.sitemap(site))
  end
end

Crawler.run
