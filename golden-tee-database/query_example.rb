require_relative 'models'

puts "=== Database Contents ==="
puts

puts "Players:"
Player.all.limit(10).each do |player|
  nickname_text = player.nickname ? " (#{player.nickname})" : ""
  remote_id_text = player.remote_id ? " [ID: #{player.remote_id}]" : ""
  puts "  - #{player.name}#{nickname_text}#{remote_id_text}"
end
puts "  ... (showing first 10 of #{Player.count} total)"

puts "\nCourses:"
Course.all.limit(10).each do |course|
  puts "  - #{course.name}"
end
puts "  ... (showing first 10 of #{Course.count} total)"

puts "\nSources:"
Source.all.each do |source|
  match_count = Match.where(source_id: source.id).count
  puts "  - #{source.name} (#{match_count} matches)"
end

puts "\n=== Sample Matches for Andy Haas ==="
andy = Player.find_by(name: "Andy Haas")

if andy
  puts "\nMatches Won:"
  andy.wins.includes(match: [:course, :source]).limit(3).each do |participation|
    match = participation.match
    # Find the opponent (the other participation in this match)
    opponent_participation = match.match_participations.where.not(player_id: andy.id).first
    opponent = opponent_participation.player
    puts "  #{andy.name} (#{participation.score}) defeated #{opponent.name} (#{opponent_participation.score})"
    puts "    at #{match.course.name}, #{match.source.name} #{match.year}"
  end

  puts "\nMatches Lost:"
  andy.losses.includes(match: [:course, :source]).limit(3).each do |participation|
    match = participation.match
    # Find the opponent (the other participation in this match)
    opponent_participation = match.match_participations.where.not(player_id: andy.id).first
    opponent = opponent_participation.player
    puts "  #{opponent.name} (#{opponent_participation.score}) defeated #{andy.name} (#{participation.score})"
    puts "    at #{match.course.name}, #{match.source.name} #{match.year}"
  end

  # Calculate win/loss record using the simpler queries
  wins_count = andy.wins.count
  losses_count = andy.losses.count
  puts "\n#{andy.name}'s Record: #{wins_count} wins - #{losses_count} losses"
end
