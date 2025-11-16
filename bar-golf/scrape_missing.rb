require_relative 'models'
require_relative 'scraper'

# Find all players without nicknames
players_to_scrape = Player.where("nickname IS NULL OR nickname = ''").where.not(remote_id: nil)

puts "Found #{players_to_scrape.count} players without nicknames to scrape"
puts

if players_to_scrape.count == 0
  puts "All players have nicknames! Nothing to do."
  exit 0
end

puts "Players to scrape:"
players_to_scrape.each do |player|
  puts "  - #{player.name} (ID: #{player.remote_id})"
end

puts
print "Continue? (y/n): "
response = gets.chomp.downcase

unless response == 'y' || response == 'yes'
  puts "Cancelled."
  exit 0
end

puts
puts "Starting scrape..."
puts "=" * 50

players_to_scrape.each_with_index do |player, index|
  puts
  puts "[#{index + 1}/#{players_to_scrape.count}] Scraping #{player.name} (ID: #{player.remote_id})"

  player_url = "https://pegttour.com/players/#{player.remote_id}"

  begin
    scraper = GoldenTeeScraper.new(player_url)
    scraper.scrape

    # Sleep for 1-2 seconds to avoid spamming the website
    if index < players_to_scrape.count - 1
      sleep_time = rand(1.0..2.0).round(1)
      puts "Sleeping for #{sleep_time} seconds..."
      sleep(sleep_time)
    end
  rescue => e
    puts "ERROR: Failed to scrape #{player.name}: #{e.message}"
    puts "Continuing with next player..."
  end
end

puts
puts "=" * 50
puts "Scraping complete!"
puts

# Show updated stats
still_missing = Player.where("nickname IS NULL OR nickname = ''").where.not(remote_id: nil).count
puts "Players still without nicknames: #{still_missing}"
