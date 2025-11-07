require 'active_record'

# Establish database connection
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: 'database.sqlite3'
)

# Define models
class Player < ActiveRecord::Base
  has_many :match_participations, dependent: :destroy
  has_many :matches, through: :match_participations

  # Associations for wins and losses that return Match records
  has_many :won_participations, -> { won }, class_name: 'MatchParticipation'
  has_many :won_matches, through: :won_participations, source: :match
  has_many :lost_participations, -> { lost }, class_name: 'MatchParticipation'
  has_many :lost_matches, through: :lost_participations, source: :match

  # Convenient methods that return MatchParticipation records
  def wins
    match_participations.won
  end

  def losses
    match_participations.lost
  end
end

class Course < ActiveRecord::Base
  has_many :matches
end

class Source < ActiveRecord::Base
  has_many :matches
end

class Match < ActiveRecord::Base
  belongs_to :player1, class_name: 'Player'
  belongs_to :player2, class_name: 'Player'
  belongs_to :course
  belongs_to :source
  has_many :match_participations, dependent: :destroy
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
        t.integer :player1_id, null: false
        t.integer :player1_score, null: false
        t.integer :player2_id, null: false
        t.integer :player2_score, null: false
        t.integer :course_id, null: false
        t.integer :source_id, null: false
        t.integer :year, null: false
        t.index :player1_id
        t.index :player2_id
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
