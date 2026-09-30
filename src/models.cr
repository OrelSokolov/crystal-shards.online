require "json"

class Shard
  include JSON::Serializable

  property full_name : String    # "owner/repo" — unique key
  property name : String         # shard name from shard.yml (fallback: repo name)
  property description : String
  property homepage : String
  property version : String
  property license : String
  property authors : String
  property stars : Int32
  property forks : Int32
  property issues : Int32
  property html_url : String
  property pushed_at : String    # ISO 8601 from GitHub
  property archived : Bool
  property topics : Array(String)
  property category : String

  def initialize(@full_name, @name, @description = "", @homepage = "",
                 @version = "", @license = "", @authors = "",
                 @stars = 0, @forks = 0, @issues = 0, @html_url = "",
                 @pushed_at = "", @archived = false,
                 @topics = [] of String, @category = "misc")
  end

  def owner : String
    full_name.split('/')[0]
  end

  def repo : String
    full_name.split('/')[1]? || full_name
  end

  def pushed_time : Time
    Time.parse_iso8601(@pushed_at) || Time.utc(1970, 1, 1)
  rescue
    Time.utc(1970, 1, 1)
  end

  def pushed_fmt : String
    pushed_time.to_s("%b %d, %Y")
  end

  def age_days : Int32
    ((Time.utc - pushed_time).total_days).to_i
  end

  # Maintenance status by repository activity:
  #   active    — pushed within the last 3 years
  #   stale     — no pushes for 3..5 years (warning)
  #   abandoned — no pushes for 5+ years, or archived
  def status : Symbol
    return :abandoned if @archived
    days = age_days
    return :abandoned if days > 5 * 365
    return :stale if days > 3 * 365
    :active
  end

  # For search scoring: lowercase haystacks, computed lazily.
  def lname : String
    @lname ||= name.downcase
  end

  def ldesc : String
    @ldesc ||= description.downcase
  end

  @lname : String? = nil
  @ldesc : String? = nil
end

struct SiteData
  include JSON::Serializable

  property generated_at : String
  property shards : Array(Shard)

  def initialize(@generated_at, @shards)
  end

  def self.load(path) : SiteData
    File.exists?(path) ? from_json(File.read(path)) : new(Time.utc.to_rfc3339, [] of Shard)
  end
end
