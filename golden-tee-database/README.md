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
- Web UI for browsing players and their statistics (Sinatra + Tailwind CSS)

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
- `course_id` - Course where match was played (foreign key to courses)
- `source_id` - Tournament/event (foreign key to sources)
- `year` - Year the match was played
- `fingerprint` - Unique hash of match data (prevents duplicates, indexed)

**Note:** Player and score information is stored in the `match_participations` table to avoid duplication. The fingerprint ensures that scraping multiple players who played each other doesn't create duplicate match records.

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

### Scrape Missing Players

```bash
ruby scrape_missing.rb
```

This script finds all players in the database without nicknames (which means their full stats haven't been scraped yet) and scrapes them automatically. It:
- Shows you the list of players to scrape
- Asks for confirmation before starting
- Scrapes each player with a 1-2 second delay between requests to avoid spamming the website
- Handles errors gracefully and continues with the next player

### Run the Web UI

```bash
ruby web.rb
```

Then visit http://localhost:4567 in your browser to:
- View all players sorted by confidence-weighted rating
- See stats including wins, losses, win %, rating, and average score
- Click on a player to see their detailed statistics
- Clean, responsive UI built with Tailwind CSS

**About the Rating System:**
The player rating uses a Bayesian average to account for sample size. A player with -25 average over 100 games will rate higher than a player with -26 over 2 games. The formula pulls players with fewer games toward the overall baseline until they have enough matches (default: 25) for their true average to dominate the rating.

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

# Get wins and losses
won_matches = player.matches.won    # Returns Match records (chainable!)
lost_matches = player.matches.lost  # Returns Match records (chainable!)

# Count wins and losses
win_count = player.matches.won.count
loss_count = player.matches.lost.count

# Get matches against a specific opponent
opponent = Player.find_by(name: "Matt Woods")
head_to_head = player.matches.against(opponent)
h2h_wins = player.matches.against(opponent).won.count
h2h_losses = player.matches.against(opponent).lost.count
# Chainable: player.matches.against(opponent).won

# Get match details
match = player.matches.won.first
# Get player's score and opponent info
andy_participation = match.match_participations.find { |p| p.player_id == player.id }
opponent_participation = match.match_participations.find { |p| p.player_id != player.id }
player_score = andy_participation.score
opponent = opponent_participation.player
opponent_score = opponent_participation.score

# Access MatchParticipation records directly if needed
player.match_participations.won     # Participations where won: true
player.match_participations.lost    # Participations where won: false

# Calculate scoring averages
all_time_avg = player.average           # All-time average score
recent_avg = player.average(2024)       # Average since 2024

# Calculate confidence-weighted rating (Bayesian average)
# Players with fewer games are pulled toward the baseline average
rating = player.rating                  # Default confidence: 25 games
rating = player.rating(confidence: 50)  # Custom confidence weight

# Get the baseline average across all players
baseline = Player.baseline_average
# Can also pass Date/Time objects: player.average(3.years.ago)

# Find matches at a specific course
course = Course.find_by(name: "LEXINGTON STABLES")
matches = Match.where(course_id: course.id)

# Find matches from a specific tournament
source = Source.find_by(name: "FLORIDA OPEN")
matches = Match.where(source_id: source.id, year: 2025)
```

## Files

- `scraper.rb` - Main scraper script
- `scrape_missing.rb` - Batch script to scrape players without nicknames
- `models.rb` - ActiveRecord models and database schema
- `web.rb` - Sinatra web UI for browsing players and stats
- `query_example.rb` - Example queries to demonstrate database usage
- `Gemfile` - Ruby gem dependencies
- `database.sqlite3` - SQLite database (created after first run)

## Dependencies

- Ruby 2.7+
- nokogiri - HTML parsing
- sqlite3 - Database
- activerecord - ORM for database management
- sinatra - Web framework
- puma - Web server
