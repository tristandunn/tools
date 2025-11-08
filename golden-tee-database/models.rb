require 'active_record'
require 'digest'

# Establish database connection
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: 'database.sqlite3'
)

# Define models
class Player < ActiveRecord::Base
  has_many :match_participations, dependent: :destroy
  has_many :matches, through: :match_participations do
    # Extend the matches association with won/lost scopes
    def won
      merge(MatchParticipation.won)
    end

    def lost
      merge(MatchParticipation.lost)
    end

    # Filter matches to only those against a specific opponent
    def against(other_player)
      # Get match IDs where the other player also participated
      other_player_match_ids = MatchParticipation.where(player_id: other_player.id).pluck(:match_id)
      where(id: other_player_match_ids)
    end
  end

  # Calculate average score for this player
  # Optional since parameter filters to matches from that date forward
  def average(since = nil)
    participations = match_participations

    if since
      # Filter to matches from the given year onward
      since_year = since.is_a?(Integer) ? since : since.year
      match_ids = Match.where("year >= ?", since_year).pluck(:id)
      participations = participations.where(match_id: match_ids)
    end

    scores = participations.pluck(:score)
    return nil if scores.empty?

    (scores.sum.to_f / scores.length).round(2)
  end

  # Calculate confidence-weighted rating using Bayesian average
  # Players with fewer games are pulled toward the baseline average
  # confidence: number of games needed to fully trust the player's average (default 25)
  def rating(confidence: 25)
    avg = average
    return nil if avg.nil?

    game_count = match_participations.count
    baseline = Player.baseline_average

    # Bayesian average: (C * baseline + n * avg) / (C + n)
    ((confidence * baseline) + (game_count * avg)) / (confidence + game_count).to_f
  end

  # Calculate the baseline average score across all players
  def self.baseline_average
    # Cache the baseline to avoid recalculating on every call
    @baseline_average ||= begin
      all_scores = MatchParticipation.pluck(:score)
      all_scores.empty? ? 0.0 : (all_scores.sum.to_f / all_scores.length)
    end
  end

  # Reset the cached baseline (call after adding new data)
  def self.reset_baseline_cache
    @baseline_average = nil
  end
end

class Course < ActiveRecord::Base
  has_many :matches
end

class Source < ActiveRecord::Base
  has_many :matches
end

class Match < ActiveRecord::Base
  belongs_to :course
  belongs_to :source
  has_many :match_participations, dependent: :destroy
  has_many :players, through: :match_participations

  # Generate a unique fingerprint for a match based on players, scores, course, source, and year
  def self.generate_fingerprint(player1_id, player1_score, player2_id, player2_score, course_id, source_id, year)
    # Sort player IDs and their scores together to ensure consistent ordering
    if player1_id < player2_id
      sorted_data = [player1_id, player1_score, player2_id, player2_score]
    else
      sorted_data = [player2_id, player2_score, player1_id, player1_score]
    end

    # Combine all match data and hash it
    fingerprint_data = [sorted_data, course_id, source_id, year].flatten.join('-')
    Digest::SHA256.hexdigest(fingerprint_data)
  end

  # Find or create a match with smart duplicate detection
  # This handles:
  # 1. First scrape: Import all rows as-is to match website totals exactly (including duplicates)
  # 2. Re-scraping: Skip matches where BOTH players already participated together with same winner
  def self.find_or_create_match(player1_id, player1_score, player2_id, player2_score, course_id, source_id, year, current_player_id:)
    fingerprint = generate_fingerprint(player1_id, player1_score, player2_id, player2_score, course_id, source_id, year)
    player_ids = [player1_id, player2_id].sort

    # Check if current player has any existing matches - if not, this is their first scrape
    # On first scrape, import everything as-is (no deduplication)
    current_player_match_count = MatchParticipation.where(player_id: current_player_id).count

    if current_player_match_count > 0
      # This is a re-scrape - check for duplicates
      existing_matches = Match.where(fingerprint: fingerprint).includes(:match_participations)

      # Check if BOTH players already participated together with the same winner
      existing_matches.each do |match|
        participant_ids = match.match_participations.pluck(:player_id).sort
        if participant_ids == player_ids
          # Both players are in this match - check if the winner is the same
          existing_winner_id = match.match_participations.find { |p| p.won == true }&.player_id
          current_winner_id = player1_id  # player1 is always the winner in our data structure

          if existing_winner_id == current_winner_id
            # Same match with same winner - skip it (prevents duplicates on re-scraping)
            return [match, false]
          end
          # Different winner - this is a tied match appearing in both tables, create new match
        end
      end
    end

    # Either first scrape (import everything), or no matching duplicates found
    # Create a new match
    existing_matches = Match.where(fingerprint: fingerprint)
    next_sequence = existing_matches.any? ? existing_matches.maximum(:sequence) + 1 : 1

    match = Match.create!(
      course_id: course_id,
      source_id: source_id,
      year: year,
      fingerprint: fingerprint,
      sequence: next_sequence
    )

    [match, true]
  end
end

class MatchParticipation < ActiveRecord::Base
  belongs_to :match
  belongs_to :player

  # Scopes for filtering by outcome
  scope :won, -> { where(won: true) }
  scope :lost, -> { where(won: false) }
end

# Create tables if they don't exist
def setup_schema
  ActiveRecord::Schema.define do
    unless ActiveRecord::Base.connection.table_exists?(:players)
      create_table :players do |t|
        t.integer :remote_id
        t.string :name, null: false
        t.string :nickname
        t.index :remote_id, unique: true
        t.index :name
      end
    else
      # Add remote_id column if it doesn't exist
      unless ActiveRecord::Base.connection.column_exists?(:players, :remote_id)
        add_column :players, :remote_id, :integer
        add_index :players, :remote_id, unique: true
      end
    end

    unless ActiveRecord::Base.connection.table_exists?(:courses)
      create_table :courses do |t|
        t.string :name, null: false
        t.index :name, unique: true
      end
    end

    unless ActiveRecord::Base.connection.table_exists?(:sources)
      create_table :sources do |t|
        t.string :name, null: false
        t.index :name, unique: true
      end
    end

    unless ActiveRecord::Base.connection.table_exists?(:matches)
      create_table :matches do |t|
        t.integer :course_id, null: false
        t.integer :source_id, null: false
        t.integer :year, null: false
        t.string :fingerprint, null: false
        t.integer :sequence, null: false, default: 1
        t.index :course_id
        t.index :source_id
        t.index :fingerprint
        t.index [:fingerprint, :sequence], unique: true
      end
    else
      # Add fingerprint column if it doesn't exist
      unless ActiveRecord::Base.connection.column_exists?(:matches, :fingerprint)
        add_column :matches, :fingerprint, :string, null: false, default: ''
        add_index :matches, :fingerprint
      end

      # Add sequence column if it doesn't exist
      unless ActiveRecord::Base.connection.column_exists?(:matches, :sequence)
        add_column :matches, :sequence, :integer, null: false, default: 1
        add_index :matches, [:fingerprint, :sequence], unique: true
      end
    end

    unless ActiveRecord::Base.connection.table_exists?(:match_participations)
      create_table :match_participations do |t|
        t.integer :match_id, null: false
        t.integer :player_id, null: false
        t.integer :score, null: false
        t.boolean :won, null: false
        t.index :match_id
        t.index :player_id
        t.index [:player_id, :won]
      end
    end
  end

  puts "Database schema created successfully!"
end

if __FILE__ == $0
  setup_schema
end
