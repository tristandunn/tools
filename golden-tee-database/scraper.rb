require 'nokogiri'
require 'open-uri'
require_relative 'models'

class GoldenTeeScraper
  def initialize(player_url)
    @player_url = player_url
    # Ensure we're using the statistics page to get all matches
    @statistics_url = player_url.sub(/\/players\/(\d+).*/, '/players/\1/statistics')
    @doc = nil
  end

  def scrape
    setup_schema
    fetch_page
    player = extract_player_info
    extract_matches(player)
    puts "\nScraping completed successfully!"
    print_summary(player)
  end

  private

  def fetch_page
    puts "Fetching #{@statistics_url}..."
    @doc = Nokogiri::HTML(URI.open(@statistics_url))
  end

  def extract_player_info
    # Extract player name and nickname
    name = @doc.css('h1').first&.text&.strip

    # Extract remote_id from URL
    remote_id_match = @player_url.match(/\/players\/(\d+)/)
    remote_id = remote_id_match ? remote_id_match[1].to_i : nil

    # Look for nickname in strong tag
    nickname = nil
    @doc.css('strong').each do |strong|
      if strong.text.strip =~ /Nickname/i
        parent = strong.parent
        text_parts = parent.text.split('Nickname')
        nickname = text_parts[1].strip if text_parts.length > 1
        break
      end
    end

    puts "\nPlayer: #{name}"
    puts "Remote ID: #{remote_id || 'N/A'}"
    puts "Nickname: #{nickname || 'N/A'}"

    player = find_or_create_player(name, remote_id)
    player.update(nickname: nickname) if nickname && player.nickname != nickname
    player
  end

  def extract_matches(player)
    matches_won = extract_matches_from_tables(player)

    puts "\nExtracted #{matches_won[:won]} matches won"
    puts "Extracted #{matches_won[:lost]} matches lost"
  end

  def extract_matches_from_tables(player)
    won_count = 0
    lost_count = 0

    # Find all tables with match data (headers include Winner and Loser)
    @doc.css('table').each do |table|
      headers = table.css('thead th').map { |th| th.text.strip }

      # Skip if not a match table
      next unless headers.include?("Winner") && headers.include?("Loser")

      # Extract rows from table body
      rows = table.css('tbody tr')

      rows.each do |row|
        begin
          cells = row.css('td')
          next if cells.length < 6

          winner_name = cells[0].text.strip
          winner_remote_id = extract_remote_id(cells[0])
          winner_score = parse_score(cells[1].text)
          loser_name = cells[2].text.strip
          loser_remote_id = extract_remote_id(cells[2])
          loser_score = parse_score(cells[3].text)
          course_name = cells[4].text.strip
          location = cells[5].text.strip

          # Parse location to extract source and year
          source_name, year = parse_location(location)

          # Skip if we couldn't parse essential data
          next unless winner_score && loser_score && year

          # Find or create players (use remote_id if available, otherwise fall back to name)
          winner = find_or_create_player(winner_name, winner_remote_id)
          loser = find_or_create_player(loser_name, loser_remote_id)

          # Find or create course
          course = Course.find_or_create_by(name: course_name)

          # Find or create source
          source = Source.find_or_create_by(name: source_name)

          # Find or create match using fingerprint (returns [match, is_new])
          match, is_new = Match.find_or_create_match(
            winner.id, winner_score,
            loser.id, loser_score,
            course.id, source.id, year
          )

          # Only create participations if this is a new match
          if is_new
            # Create match participations for both players
            MatchParticipation.create!(
              match_id: match.id,
              player_id: winner.id,
              score: winner_score,
              won: true
            )

            MatchParticipation.create!(
              match_id: match.id,
              player_id: loser.id,
              score: loser_score,
              won: false
            )
          end

          # Track if this was a win or loss for the current player (only count new matches)
          if is_new
            if winner.id == player.id
              won_count += 1
            elsif loser.id == player.id
              lost_count += 1
            end
          end
        rescue => e
          puts "Error processing row: #{e.message}"
        end
      end
    end

    { won: won_count, lost: lost_count }
  end

  def parse_score(score_text)
    # Extract score from text like "(-30)" or "-30"
    match = score_text.match(/-?\d+/)
    match ? match[0].to_i : nil
  end

  def parse_location(location)
    # Location format: "Florida Open 2025" or similar
    # Extract the year (last 4 digits)
    year_match = location.match(/\b(20\d{2})\b/)
    year = year_match ? year_match[1].to_i : nil

    # Extract source name (everything before the year)
    if year
      source_name = location.gsub(/\b#{year}\b/, '').strip
    else
      source_name = location
    end

    [source_name, year]
  end

  def extract_remote_id(cell)
    # Extract remote player ID from link like /players/863
    link = cell.css('a').first
    return nil unless link

    href = link['href']
    match = href.match(/\/players\/(\d+)/)
    match ? match[1].to_i : nil
  end

  def find_or_create_player(name, remote_id)
    # Try to find by remote_id first if available
    if remote_id
      player = Player.find_by(remote_id: remote_id)
      if player
        # Update name if it changed
        player.update(name: name) if player.name != name
        return player
      end
    end

    # Fall back to finding by name
    player = Player.find_by(name: name)
    if player
      # Update remote_id if we now have it
      player.update(remote_id: remote_id) if remote_id && player.remote_id.nil?
      return player
    end

    # Create new player
    Player.create!(name: name, remote_id: remote_id)
  end

  def print_summary(player)
    total_matches = player.matches.count
    total_players = Player.count
    total_courses = Course.count
    total_sources = Source.count

    puts "\n" + "="*50
    puts "Summary:"
    puts "="*50
    puts "Total players in database: #{total_players}"
    puts "Total courses: #{total_courses}"
    puts "Total sources: #{total_sources}"
    puts "Total matches for #{player.name}: #{total_matches}"
    puts "="*50
  end
end

if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: ruby scraper.rb <player_url>"
    puts "Example: ruby scraper.rb https://pegttour.com/players/863"
    exit 1
  end

  scraper = GoldenTeeScraper.new(ARGV[0])
  scraper.scrape
end
