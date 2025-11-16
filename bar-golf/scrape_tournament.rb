require 'nokogiri'
require 'open-uri'
require_relative 'models'

class TournamentScraper
  def initialize(tournament_url)
    @tournament_url = tournament_url
    @doc = nil
  end

  def scrape
    setup_schema
    fetch_page
    tournament = extract_tournament_info
    extract_results(tournament)
    puts "\nTournament scraping completed successfully!"
    print_summary(tournament)
  end

  private

  def fetch_page
    puts "Fetching #{@tournament_url}..."
    @doc = Nokogiri::HTML(URI.open(@tournament_url))
  rescue => e
    puts "Error fetching page: #{e.message}"
    exit 1
  end

  def extract_tournament_info
    # Extract tournament name and year from URL
    # Example: https://pegttour.com/tournaments/2025/florida-open/results
    url_match = @tournament_url.match(/\/tournaments\/(\d+)\/([^\/]+)/)

    if url_match
      year = url_match[1].to_i
      slug = url_match[2]
      # Convert slug to title case name (e.g., "florida-open" -> "Florida Open")
      name = slug.split('-').map(&:capitalize).join(' ')
    else
      puts "Could not parse tournament info from URL"
      exit 1
    end

    puts "\nTournament: #{name} (#{year})"

    # Find or create tournament
    tournament = Tournament.find_or_create_by(url: @tournament_url) do |t|
      t.name = name
      t.year = year
    end

    # Update name and year if they've changed
    tournament.update(name: name, year: year) if tournament.name != name || tournament.year != year

    tournament
  end

  def extract_results(tournament)
    results_count = 0

    # Find all tables with tournament results
    @doc.css('table').each do |table|
      headers = table.css('thead th').map { |th| th.text.strip }

      # Look for tables with Bracket, Place, Name, and Points columns
      next unless headers.include?("Bracket") && headers.include?("Place") && headers.include?("Name")

      # Get column indices
      bracket_idx = headers.index("Bracket")
      place_idx = headers.index("Place")
      name_idx = headers.index("Name")
      points_idx = headers.index("Points")

      rows = table.css('tbody tr')

      rows.each do |row|
        begin
          cells = row.css('td')
          next if cells.length < 3

          bracket = cells[bracket_idx]&.text&.strip
          place = cells[place_idx]&.text&.strip
          name_cell = cells[name_idx]
          points = points_idx ? cells[points_idx]&.text&.strip&.to_i : nil

          # Skip if bracket or place is missing
          next if bracket.nil? || bracket.empty? || place.nil? || place.empty?

          # Extract player name and remote_id
          player_link = name_cell.css('a').first
          next unless player_link

          player_name = player_link.text.strip
          remote_id = extract_remote_id(player_link)

          # Find or create player
          player = find_or_create_player(player_name, remote_id)

          # Create or update tournament result
          result = TournamentResult.find_or_initialize_by(
            tournament_id: tournament.id,
            player_id: player.id
          )

          result.place = place
          result.bracket = bracket
          result.points = points
          result.save!

          results_count += 1
        rescue => e
          puts "Error processing row: #{e.message}"
          # Debug output
          puts "  Bracket: #{bracket.inspect}"
          puts "  Place: #{place.inspect}"
          puts "  Cells count: #{cells.length}"
        end
      end
    end

    puts "Extracted #{results_count} tournament results"
  end

  def extract_remote_id(link)
    # Extract remote player ID from link like /players/863
    href = link['href']
    match = href&.match(/\/players\/(\d+)/)
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

  def print_summary(tournament)
    total_results = tournament.tournament_results.count
    total_players = tournament.players.count

    puts "\n" + "="*50
    puts "Summary:"
    puts "="*50
    puts "Tournament: #{tournament.name} (#{tournament.year})"
    puts "Total results: #{total_results}"
    puts "Total unique players: #{total_players}"
    puts "="*50
  end
end

if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: ruby scrape_tournament.rb <tournament_results_url>"
    puts "Example: ruby scrape_tournament.rb https://pegttour.com/tournaments/2025/florida-open/results"
    exit 1
  end

  scraper = TournamentScraper.new(ARGV[0])
  scraper.scrape
end
