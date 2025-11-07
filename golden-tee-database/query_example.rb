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
  Match.where(player1_id: andy.id).limit(3).each do |match|
    opponent = Player.find(match.player2_id)
    course = Course.find(match.course_id)
    source = Source.find(match.source_id)
    puts "  #{andy.name} (#{match.player1_score}) defeated #{opponent.name} (#{match.player2_score})"
    puts "    at #{course.name}, #{source.name} #{match.year}"
  end

  puts "\nMatches Lost:"
  Match.where(player2_id: andy.id).limit(3).each do |match|
    opponent = Player.find(match.player1_id)
    course = Course.find(match.course_id)
    source = Source.find(match.source_id)
    puts "  #{opponent.name} (#{match.player1_score}) defeated #{andy.name} (#{match.player2_score})"
    puts "    at #{course.name}, #{source.name} #{match.year}"
  end

  # Calculate win/loss record
  wins = Match.where(player1_id: andy.id).count
  losses = Match.where(player2_id: andy.id).count
  puts "\n#{andy.name}'s Record: #{wins} wins - #{losses} losses"
end
