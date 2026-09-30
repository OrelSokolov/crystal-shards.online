require "ecr"
require "json"

# Shared page rendering for the crawler (pre-generated static pages) and
# the server (dynamic /search). Zero client-side JavaScript.

module Render
  BASE_URL = ENV.fetch("BASE_URL", "https://crystal-shards.online")

  # Cache-busting version for /assets/style.css: the file's mtime, so a
  # changed stylesheet gets a new URL and browsers never serve stale CSS.
  def self.asset_v : String
    @@asset_v ||= begin
      path = File.join(ENV.fetch("PUBLIC_DIR", "public"), "assets/style.css")
      File.info?(path).try(&.modification_time.to_unix.to_s) || "1"
    end
  end

  @@asset_v : String? = nil

  class PageView
    def initialize(@title : String, @desc : String, @canonical : String, @content : String)
    end

    ECR.def_to_s("templates/layout.ecr")
  end

  class CardView
    def initialize(@shard : Shard)
    end

    ECR.def_to_s("templates/_card.ecr")
  end

  class RowView
    def initialize(@shard : Shard)
    end

    ECR.def_to_s("templates/_row.ecr")
  end

  class IndexView
    def initialize(@top : Array(Shard), @recent : Array(Shard),
                   @newest : Array(Shard), @chart : String,
                   @total : Int32, @updated : String)
    end

    ECR.def_to_s("templates/index.ecr")
  end

  class SearchView
    def initialize(@q : String, @results : Array(Shard), @total : Int32,
                   @sort : String?, @filter5 : Bool)
    end

    ECR.def_to_s("templates/search.ecr")
  end

  class ShardView
    def initialize(@shard : Shard, @related : Array(Shard))
    end

    ECR.def_to_s("templates/shard.ecr")
  end

  class CategoriesView
    def initialize(@cats : Array(Tuple(String, Int32)))
    end

    ECR.def_to_s("templates/categories.ecr")
  end

  class CategoryView
    def initialize(@slug : String, @title : String, @shards : Array(Shard),
                   @sort : String?, @filter5 : Bool)
    end

    ECR.def_to_s("templates/category.ecr")
  end

  class NewView
    def initialize(@period : String, @month : String?, @shards : Array(Shard), @total : Int32)
    end

    ECR.def_to_s("templates/new.ecr")
  end

  class ActivityView
    def initialize(@chart : String, @total : Int32, @since : String)
    end

    ECR.def_to_s("templates/activity.ecr")
  end

  class ErrorView
    def initialize(@code : Int32, @message : String)
    end

    ECR.def_to_s("templates/error.ecr")
  end

  def self.page(title, desc, path, content) : String
    PageView.new(title, desc, "#{BASE_URL}#{path}", content).to_s
  end

  def self.card(s : Shard) : String
    CardView.new(s).to_s
  end

  def self.row(s : Shard) : String
    RowView.new(s).to_s
  end

  def self.category_counts(shards : Array(Shard)) : Array(Tuple(String, Int32))
    counts = Hash(String, Int32).new(0)
    shards.each { |s| counts[s.category] += 1 }
    counts.to_a.sort_by! { |(slug, n)| CATEGORY_ORDER.index(slug) || CATEGORY_ORDER.size }
  end

  def self.index(site : SiteData) : String
    top = site.shards.sort_by { |s| -s.stars }.first(10)
    recent = site.shards.sort_by { |s| -(s.pushed_time.to_unix) }.first(10)
    newest = site.shards.sort_by { |s| -(s.created_time.to_unix) }.first(10)
    chart = activity_chart(site)
    content = IndexView.new(top, recent, newest, chart, site.shards.size, site.generated_at).to_s
    page("Crystal Shards — catalog of Crystal libraries",
         "Searchable catalog of Crystal shards on GitHub: #{site.shards.size} libraries organized by category.",
         "/", content)
  end

  NEW_PERIODS = {"today" => 1, "week" => 7, "month" => 30, "year" => 365}

  # Inline SVG bar chart: shards created per month. Bars are links to the
  # per-month listing (/new?month=YYYY-MM). Server-side, no JavaScript.
  def self.activity_chart(site : SiteData, months = 36, full_history = false) : String
    this_month = Time.utc.at_beginning_of_month
    start =
      if full_history
        first = site.shards.map(&.created_time).select { |t| t.year > 1970 }.min? || this_month
        first.at_beginning_of_month
      else
        this_month - months.months
      end
    span = (this_month.year - start.year) * 12 + (this_month.month - start.month) + 1

    buckets = Array(Int32).new(span, 0)
    site.shards.each do |s|
      t = s.created_time
      next if t.year <= 1970
      idx = (t.year - start.year) * 12 + (t.month - start.month)
      buckets[idx] += 1 if idx >= 0 && idx < span
    end

    w = full_history ? 1100f64 : 760f64
    h = full_history ? 220f64 : 140f64
    pad = 2f64
    label_h = 18f64
    bw = (w - pad * 2) / span
    label_every = full_history ? 12 : 6
    max = buckets.max? || 1
    max = 1 if max < 1

    String.build do |io|
      io << %(<svg class="chart" viewBox="0 -30 #{w.to_i} #{(h + label_h + 30).to_i}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="New shards by month">)
      span.times do |i|
        count = buckets[i]
        x = pad + i * bw
        t = start + i.months
        ym = t.to_s("%Y-%m")
        label = t.to_s("%b %Y")
        io << %(<g class="bar-g">)
        io << %(<a class="bar-link" href="/new?month=#{ym}">)
        # invisible hit zone spanning the whole column: gapless hover,
        # no dead space between bars (and zero months stay hoverable)
        io << %(<rect class="hit" x="#{x.round(2)}" y="-30" width="#{bw.round(2)}" height="#{(h + 30 + label_h).round(2)}" pointer-events="all"/>)
        if count > 0
          bh = count / max * (h - 6)
          bh = 2 if bh < 2
          io << %(<rect class="bar" x="#{x.round(2)}" y="#{(h - bh).round(2)}" width="#{(bw - 2).round(2)}" height="#{bh.round(2)}" rx="1"><title>#{label}: #{count} new shard#{count == 1 ? "" : "s"}</title></rect>)
        end
        io << %(</a>)
        # hover readout: fixed top-left corner, big count + month
        io << %(<text class="chart-tip" x="6" y="8"><tspan class="c">#{count}</tspan><tspan class="m" dx="8">#{label}</tspan></text>)
        io << %(</g>)
      end
      (0...span).step(label_every) do |i|
        t = start + i.months
        x = pad + i * bw
        text = full_history ? t.to_s("%Y") : t.to_s("%b %y")
        io << %(<text class="chart-label" x="#{x.round(2)}" y="#{(h + label_h - 4).to_i}">#{text}</text>)
      end
      io << "</svg>"
    end
  end

  def self.month_title(month : String) : String
    Time.parse("#{month}-01", "%Y-%m-%d", Time::Location::UTC).to_s("%B %Y")
  rescue
    month
  end

  def self.new_shards(period : String, month : String?, shards : Array(Shard), total : Int32) : String
    content = NewView.new(period, month, shards, total).to_s
    title = month ? "New shards — #{month_title(month)}" : "New shards — last #{period}"
    page(title, "Crystal shards created recently", "/new", content)
  end

  def self.activity(site : SiteData) : String
    since = site.shards.map(&.created_time).select { |t| t.year > 1970 }.min?
    content = ActivityView.new(activity_chart(site, full_history: true),
                               site.shards.size,
                               since.try(&.to_s("%B %Y")) || "—").to_s
    page("Activity — Crystal Shards", "Crystal shards created per month, full history", "/activity", content)
  end

  def self.search(q : String, results : Array(Shard), total : Int32,
                  sort : String? = nil, filter5 : Bool = false) : String
    content = SearchView.new(q, results, total, sort, filter5).to_s
    page("#{q.empty? ? "Search" : "#{q} — search results"}", "Crystal shards matching “#{q}”", "/search", content)
  end

  def self.shard_page(s : Shard, all : Array(Shard)) : String
    related = all.select(&.category.==(s.category))
                 .reject(&.full_name.==(s.full_name))
                 .sort_by { |s| -s.stars }
                 .first(6)
    content = ShardView.new(s, related).to_s
    desc = s.description.empty? ? "#{s.name} — a Crystal shard" : s.description
    page("#{s.name} · #{s.full_name}", desc, "/shards/#{s.full_name}", content)
  end

  def self.categories(site : SiteData) : String
    content = CategoriesView.new(category_counts(site.shards)).to_s
    page("Categories — Crystal Shards", "All Crystal shard categories", "/categories", content)
  end

  def self.category(slug : String, shards : Array(Shard),
                    sort : String? = nil, filter5 : Bool = false) : String
    content = CategoryView.new(slug, category_title(slug), shards, sort, filter5).to_s
    page("#{category_title(slug)} — Crystal Shards",
         "Crystal shards in #{category_title(slug)}", "/category/#{slug}", content)
  end

  def self.error(code : Int32, message : String) : String
    content = ErrorView.new(code, message).to_s
    page("#{code}", message, "/#{code}", content)
  end

  def self.sitemap(site : SiteData) : String
    String.build do |io|
      io << %(<?xml version="1.0" encoding="UTF-8"?>\n)
      io << %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n)
      url(io, "/")
      url(io, "/categories")
      category_counts(site.shards).each { |(slug, _)| url(io, "/category/#{slug}") }
      site.shards.each { |s| url(io, "/shards/#{s.full_name}") }
      io << "</urlset>\n"
    end
  end

  private def self.url(io, path : String)
    io << "<url><loc>" << HTML.escape("#{BASE_URL}#{path}") << "</loc></url>\n"
  end

  # Query-string builders for sort/filter controls (no-JS, plain links).
  def self.search_url(q : String, sort : String?, filter5 : Bool) : String
    params = [] of String
    params << "q=#{URI.encode_path(q)}" unless q.empty?
    params << "sort=#{sort}" if sort && !sort.empty?
    params << "filter=5y" if filter5
    params.empty? ? "/search" : "/search?#{params.join("&")}"
  end

  def self.category_url(slug : String, sort : String?, filter5 : Bool) : String
    params = [] of String
    params << "sort=#{sort}" if sort && !sort.empty?
    params << "filter=5y" if filter5
    params.empty? ? "/category/#{slug}" : "/category/#{slug}?#{params.join("&")}"
  end
end
