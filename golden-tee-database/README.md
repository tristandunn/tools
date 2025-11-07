# Golden Tee Database

A Ruby web scraper that extracts player data and match results from pegttour.com and stores them in a SQLite database.

## Features

- Scrapes player profiles including name, nickname, and remote ID
- Extracts match results (wins and losses)
- Automatically finds or creates players, courses, and sources
- Stores scores for both players in each match
- Uses a join table (match_participations) for simple player match queries
- Tracks pegttour.com player IDs for easy reference and duplicate prevention
- Uses ActiveRecord for easy database management

## Database Schema

### Players
- `id` - Primary key
- `remote_id` - Player ID from pegttour.com (unique, indexed)
- `name` - Player name
- `nickname` - Player nickname (optional)

### Courses
- `id` - Primary key
- `name` - Course name (unique)

### Sources
- `id` - Primary key
- `name` - Tournament/event name (unique)

### Matches
- `id` - Primary key
- `player1_id` - Winner (foreign key to players)
- `player1_score` - Winner's score
- `player2_id` - Loser (foreign key to players)
- `player2_score` - Loser's score
- `course_id` - Course where match was played (foreign key to courses)
- `source_id` - Tournament/event (foreign key to sources)
- `year` - Year the match was played

### Match Participations
- `id` - Primary key
- `match_id` - The match (foreign key to matches)
- `player_id` - The player (foreign key to players)
- `score` - Player's score in this match
- `won` - Whether the player won (boolean)

**Note:** Each match creates 2 match_participations (one per player), making it easy to query all matches for a specific player without complex joins.

## Installation

```bash
bundle install
```

## Usage

### Scrape a Player's Data

```bash
ruby scraper.rb https://pegttour.com/players/863
```

This will:
1. Create the database tables if they don't exist
2. Fetch the player's statistics page (automatically converts to `/players/{id}/statistics`)
3. Extract player information and ALL matches (wins and losses)
4. Store everything in `database.sqlite3`

**Note:** The scraper automatically uses the statistics page to get the complete match history, not just the first page of results.

### Query the Database

```bash
ruby query_example.rb
```

This shows example queries including:
- All players with nicknames
- All courses and sources
- Sample matches for Andy Haas
- Win/loss record

### Custom Queries

You can create your own query scripts using the ActiveRecord models:

```ruby
require_relative 'models'

# Find a player by name
player = Player.find_by(name: "Andy Haas")

# Find a player by remote_id (pegttour.com ID)
player = Player.find_by(remote_id: 863)

# Get all matches for a player
all_matches = player.matches
all_participations = player.match_participations

# Get wins and losses (multiple ways)
won_matches = player.won_matches       # Returns Match records (can chain queries)
lost_matches = player.lost_matches     # Returns Match records (can chain queries)
wins = player.wins                     # Returns MatchParticipation records
losses = player.losses                 # Returns MatchParticipation records

# Count wins and losses
win_count = player.won_matches.count   # Count using Match records
loss_count = player.lost_matches.count # Count using Match records
# OR
win_count = player.wins.count          # Count using MatchParticipation records
loss_count = player.losses.count       # Count using MatchParticipation records

# Use scopes directly on match_participations
player.match_participations.won        # MatchParticipations where won: true
player.match_participations.lost       # MatchParticipations where won: false

# Get match details from a participation
participation = player.wins.first
match = participation.match
score = participation.score
opponent_participation = match.match_participations.where.not(player_id: player.id).first
opponent = opponent_participation.player

# Find matches at a specific course
course = Course.find_by(name: "LEXINGTON STABLES")
matches = Match.where(course_id: course.id)

# Find matches from a specific tournament
source = Source.find_by(name: "FLORIDA OPEN")
matches = Match.where(source_id: source.id, year: 2025)
```

## Files

- `scraper.rb` - Main scraper script
- `models.rb` - ActiveRecord models and database schema
- `query_example.rb` - Example queries to demonstrate database usage
- `Gemfile` - Ruby gem dependencies
- `database.sqlite3` - SQLite database (created after first run)

## Dependencies

- Ruby 2.7+
- nokogiri - HTML parsing
- sqlite3 - Database
- activerecord - ORM for database management
