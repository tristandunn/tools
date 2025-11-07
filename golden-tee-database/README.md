# Golden Tee Database

A Ruby web scraper that extracts player data and match results from pegttour.com and stores them in a SQLite database.

## Features

- Scrapes player profiles including name and nickname
- Extracts match results (wins and losses)
- Automatically finds or creates players, courses, and sources
- Stores scores for both players in each match
- Uses ActiveRecord for easy database management

## Database Schema

### Players
- `id` - Primary key
- `name` - Player name (unique)
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

# Find a player
player = Player.find_by(name: "Andy Haas")

# Get all matches for a player
wins = Match.where(player1_id: player.id)
losses = Match.where(player2_id: player.id)

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
