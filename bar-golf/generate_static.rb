#!/usr/bin/env ruby

require 'erb'
require 'fileutils'
require_relative 'models'

# Setup schema to ensure database is ready
setup_schema

# Reset baseline cache to ensure fresh calculation with current data
Player.reset_baseline_cache

# Get all players with their stats (same logic as web.rb)
@players = Player.all.map do |player|
  wins = player.matches.won.count
  losses = player.matches.lost.count
  total = wins + losses
  win_pct = total > 0 ? ((wins.to_f / total) * 100).round(1) : 0
  avg = player.average
  rating = player.rating
  elo = player.elo_rating || 1500.0
  latest_year = player.matches.maximum(:year) || 1980

  {
    player: player,
    wins: wins,
    losses: losses,
    total: total,
    win_pct: win_pct,
    average: avg,
    rating: rating,
    elo: elo,
    latest_year: latest_year
  }
end

# Filter out players with no wins
@players.reject! { |p| p[:wins] == 0 }

# Filter out players without nicknames (means we haven't scraped their full stats)
@players.reject! { |p| p[:player].nickname.nil? || p[:player].nickname.empty? }

# Sort by ELO rating (descending - higher ELO = better player)
@players.sort_by! { |p| p[:elo] }.reverse!

# Read the web.rb file to extract templates
web_content = File.read(File.join(__dir__, 'web.rb'), encoding: 'UTF-8')

# Extract layout template
layout_match = web_content.match(/^@@ layout\n(.*?)^@@/m)
layout_template = layout_match ? layout_match[1] : nil

# Extract index template
index_match = web_content.match(/^@@ index\n(.*?)(?:^@@|\z)/m)
index_template = index_match ? index_match[1] : nil

unless layout_template && index_template
  puts "Error: Could not extract templates from web.rb"
  exit 1
end

# Render the index content
index_html = ERB.new(index_template, trim_mode: '-').result(binding)

# Replace <%= yield %> with the index content in the layout
layout_with_content = layout_template.gsub('<%= yield %>', index_html)

# Render the layout
layout_html = ERB.new(layout_with_content, trim_mode: '-').result(binding)

# Create output directory if it doesn't exist
docs_dir = File.expand_path('../docs', __dir__)
output_dir = File.join(docs_dir, 'bar-golf')
FileUtils.mkdir_p(output_dir)

# Save the HTML to the output directory as index.html
output_file = File.join(output_dir, 'index.html')
File.write(output_file, layout_html)

puts "Static HTML generated successfully!"
puts "Output: #{output_file}"
puts "Players: #{@players.length}"
puts "File size: #{File.size(output_file)} bytes"
