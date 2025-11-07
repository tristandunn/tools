require 'active_record'

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
        t.index :course_id
        t.index :source_id
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
