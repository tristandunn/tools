require 'sinatra'
require_relative 'models'

# Configure Sinatra
set :port, 4567
set :bind, '0.0.0.0'

# Home page - list all players
get '/' do
  # Reset baseline cache to ensure fresh calculation with current data
  Player.reset_baseline_cache

  # Get all players with their stats
  @players = Player.all.map do |player|
    wins = player.matches.won.count
    losses = player.matches.lost.count
    total = wins + losses
    win_pct = total > 0 ? ((wins.to_f / total) * 100).round(1) : 0
    avg = player.average
    rating = player.rating
    elo = player.elo_rating || 1500.0

    {
      player: player,
      wins: wins,
      losses: losses,
      total: total,
      win_pct: win_pct,
      average: avg,
      rating: rating,
      elo: elo
    }
  end

  # Filter out players with no wins
  @players.reject! { |p| p[:wins] == 0 }

  # Filter out players without nicknames (means we haven't scraped their full stats)
  @players.reject! { |p| p[:player].nickname.nil? || p[:player].nickname.empty? }

  # Sort by ELO rating (descending - higher ELO = better player)
  @players.sort_by! { |p| p[:elo] }.reverse!

  erb :index
end

# Player detail page
get '/players/:id' do
  @player = Player.find(params[:id])
  @wins = @player.matches.won.count
  @losses = @player.matches.lost.count
  @total = @wins + @losses
  @win_pct = @total > 0 ? ((@wins.to_f / @total) * 100).round(1) : 0
  @average = @player.average
  @rating = @player.rating
  @elo = @player.elo_rating || 1500.0

  erb :player
end

__END__

@@ layout
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Golden Tee Database</title>
  <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-50">
  <div class="min-h-screen">
    <nav class="bg-white shadow-sm">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between h-16">
          <div class="flex">
            <div class="flex-shrink-0 flex items-center">
              <a href="/" class="text-xl font-bold text-gray-900">
                🏌️ Golden Tee Database
              </a>
            </div>
          </div>
        </div>
      </div>
    </nav>

    <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <%= yield %>
    </main>
  </div>

  <script>
    // Filter functionality
    function filterTable() {
      const playerName = document.getElementById('player-name').value.toLowerCase().trim();
      const minMatches = parseInt(document.getElementById('min-matches').value) || 0;
      const minAverage = parseFloat(document.getElementById('min-average').value) || -999;
      const rows = document.querySelectorAll('tbody tr');
      let visibleCount = 0;

      rows.forEach(row => {
        const name = row.dataset.name || '';
        const total = parseInt(row.dataset.total) || 0;
        const average = parseFloat(row.dataset.average) || -999;

        // Check if name matches (if search term provided)
        const nameMatches = !playerName || name.includes(playerName);

        // In golf, lower scores are better, so <= for average (e.g., -30 is better than -20)
        if (nameMatches && total >= minMatches && average <= minAverage) {
          row.style.display = '';
          visibleCount++;
        } else {
          row.style.display = 'none';
        }
      });

      // Update visible count
      document.getElementById('visible-count').textContent = visibleCount;
    }

    // Add event listeners
    document.addEventListener('DOMContentLoaded', () => {
      const playerNameInput = document.getElementById('player-name');
      const minMatchesInput = document.getElementById('min-matches');
      const minAverageInput = document.getElementById('min-average');

      if (playerNameInput) {
        playerNameInput.addEventListener('input', filterTable);
      }

      if (minMatchesInput) {
        minMatchesInput.addEventListener('input', filterTable);
      }

      if (minAverageInput) {
        minAverageInput.addEventListener('input', filterTable);
      }

      // Filter on page load with default values
      filterTable();
    });
  </script>
</body>
</html>

@@ index
<div class="mb-6">
  <h1 class="text-3xl font-bold text-gray-900">Players</h1>
  <p class="mt-2 text-sm text-gray-600">
    <span id="visible-count"><%= @players.length %></span> of <%= @players.length %> players shown
  </p>
</div>

<div class="mb-4 bg-white shadow-sm rounded-lg p-4">
  <div class="flex flex-wrap items-center gap-4">
    <div class="flex items-center gap-2">
      <label for="player-name" class="text-sm font-medium text-gray-700">
        Player Name:
      </label>
      <input
        type="text"
        id="player-name"
        placeholder="Search..."
        class="px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 sm:text-sm w-48"
      />
    </div>
    <div class="flex items-center gap-2">
      <label for="min-matches" class="text-sm font-medium text-gray-700">
        Minimum Matches:
      </label>
      <input
        type="number"
        id="min-matches"
        value="10"
        min="0"
        class="px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 sm:text-sm w-24"
      />
    </div>
    <div class="flex items-center gap-2">
      <label for="min-average" class="text-sm font-medium text-gray-700">
        Minimum Average:
      </label>
      <input
        type="number"
        id="min-average"
        value="-15"
        step="1"
        class="px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 sm:text-sm w-24"
      />
    </div>
  </div>
</div>

<div class="bg-white shadow-sm rounded-lg overflow-hidden">
  <table class="min-w-full divide-y divide-gray-200">
    <thead class="bg-gray-50">
      <tr>
        <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
          Rank
        </th>
        <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
          Player
        </th>
        <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
          Record
        </th>
        <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
          Win %
        </th>
        <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
          ELO Rating
        </th>
        <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
          Avg Score
        </th>
        <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
          Total Matches
        </th>
      </tr>
    </thead>
    <tbody class="bg-white divide-y divide-gray-200">
      <% @players.each_with_index do |stats, index| %>
        <tr class="hover:bg-gray-50" data-total="<%= stats[:total] %>" data-average="<%= stats[:average] || -999 %>" data-name="<%= stats[:player].name.downcase %>">
          <td class="px-6 py-4 whitespace-nowrap text-sm font-semibold text-gray-700">
            #<%= index + 1 %>
          </td>
          <td class="px-6 py-4 whitespace-nowrap">
            <div class="flex items-center">
              <div>
                <div class="text-sm font-medium text-gray-900">
                  <a href="https://pegttour.com/players/<%= stats[:player].remote_id %>" class="hover:text-blue-600" target="_blank">
                    <%= stats[:player].name %>
                  </a>
                </div>
                <% if stats[:player].nickname %>
                  <div class="text-sm text-gray-500">
                    "<%= stats[:player].nickname %>"
                  </div>
                <% end %>
              </div>
            </div>
          </td>
          <td class="px-6 py-4 whitespace-nowrap">
            <div class="text-sm text-gray-900">
              <span class="text-green-600 font-semibold"><%= stats[:wins] %>W</span>
              -
              <span class="text-red-600 font-semibold"><%= stats[:losses] %>L</span>
            </div>
          </td>
          <td class="px-6 py-4 whitespace-nowrap">
            <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full <%= stats[:win_pct] >= 60 ? 'bg-green-100 text-green-800' : stats[:win_pct] >= 50 ? 'bg-yellow-100 text-yellow-800' : 'bg-red-100 text-red-800' %>">
              <%= stats[:win_pct] %>%
            </span>
          </td>
          <td class="px-6 py-4 whitespace-nowrap text-sm font-semibold text-gray-900">
            <%= sprintf("%.2f", stats[:elo]) %>
          </td>
          <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
            <%= stats[:average] || 'N/A' %>
          </td>
          <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
            <%= stats[:total] %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>

@@ player
<div class="mb-6">
  <a href="/" class="text-sm text-blue-600 hover:text-blue-800 mb-4 inline-block">&larr; Back to Players</a>
  <h1 class="text-3xl font-bold text-gray-900"><%= @player.name %></h1>
  <% if @player.nickname %>
    <p class="mt-1 text-lg text-gray-600">"<%= @player.nickname %>"</p>
  <% end %>
</div>

<div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-5 mb-8">
  <div class="bg-white overflow-hidden shadow rounded-lg">
    <div class="px-4 py-5 sm:p-6">
      <dt class="text-sm font-medium text-gray-500 truncate">Record</dt>
      <dd class="mt-1 text-3xl font-semibold text-gray-900">
        <span class="text-green-600"><%= @wins %></span>-<span class="text-red-600"><%= @losses %></span>
      </dd>
    </div>
  </div>

  <div class="bg-white overflow-hidden shadow rounded-lg">
    <div class="px-4 py-5 sm:p-6">
      <dt class="text-sm font-medium text-gray-500 truncate">Win Percentage</dt>
      <dd class="mt-1 text-3xl font-semibold text-gray-900"><%= @win_pct %>%</dd>
    </div>
  </div>

  <div class="bg-white overflow-hidden shadow rounded-lg">
    <div class="px-4 py-5 sm:p-6">
      <dt class="text-sm font-medium text-gray-500 truncate">ELO Rating</dt>
      <dd class="mt-1 text-3xl font-semibold text-gray-900"><%= sprintf("%.2f", @elo) %></dd>
    </div>
  </div>

  <div class="bg-white overflow-hidden shadow rounded-lg">
    <div class="px-4 py-5 sm:p-6">
      <dt class="text-sm font-medium text-gray-500 truncate">Average Score</dt>
      <dd class="mt-1 text-3xl font-semibold text-gray-900"><%= @average || 'N/A' %></dd>
    </div>
  </div>

  <div class="bg-white overflow-hidden shadow rounded-lg">
    <div class="px-4 py-5 sm:p-6">
      <dt class="text-sm font-medium text-gray-500 truncate">Total Matches</dt>
      <dd class="mt-1 text-3xl font-semibold text-gray-900"><%= @total %></dd>
    </div>
  </div>
</div>
