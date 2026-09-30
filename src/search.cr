# In-memory search, rubygems-style ranking without any external engine.
# Corpus is ~10k records, so a scoring scan per query is well under a
# millisecond — no inverted index needed.

class ShardSearch
  def initialize(@shards : Array(Shard))
  end

  def query(raw_q : String, limit = 30) : Array(Shard)
    q = raw_q.strip.downcase
    return [] of Shard if q.empty?

    tokens = q.split(/\s+/).reject(&.empty?)

    scored = Array({Int32, Shard}).new
    @shards.each do |s|
      score = score_of(s, q, tokens)
      scored << {score, s} if score > 0
    end

    scored.sort_by! { |(score, s)| {-score, -s.stars, s.lname} }
    scored.first(limit).map &.[1]
  end

  private def score_of(s : Shard, q : String, tokens : Array(String)) : Int32
    score = 0
    name = s.lname

    if name == q
      score += 1000
    elsif name.starts_with?(q)
      score += 500
    elsif name.includes?(q)
      score += 250
    end

    tokens.each do |t|
      if name.starts_with?(t)
        score += 200
      elsif name.includes?(t)
        score += 100
      end
      if s.topics.any?(&.downcase.includes?(t))
        score += 80
      end
      if s.ldesc.includes?(t)
        score += 30
      end
      if s.full_name.downcase.includes?(t)
        score += 40
      end
    end

    # A dash of popularity so equal textual matches rank the popular one first.
    score > 0 ? score + Math.min(s.stars // 100, 20) : 0
  end
end
