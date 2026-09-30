require "ecr"
require "json"

# Shared page rendering for the crawler (pre-generated static pages) and
# the server (dynamic /search). Zero client-side JavaScript.

module Render
  BASE_URL = ENV.fetch("BASE_URL", "https://crystal-shards.online")

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
                   @cats : Array(Tuple(String, Int32)), @total : Int32, @updated : String)
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
    top = site.shards.sort_by { |s| -s.stars }.first(12)
    recent = site.shards.sort_by { |s| -(s.pushed_time.to_unix) }.first(12)
    content = IndexView.new(top, recent, category_counts(site.shards),
                            site.shards.size, site.generated_at).to_s
    page("Crystal Shards — catalog of Crystal libraries",
         "Searchable catalog of Crystal shards on GitHub: #{site.shards.size} libraries organized by category.",
         "/", content)
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
