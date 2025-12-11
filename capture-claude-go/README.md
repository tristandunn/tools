# capture-claude

A Go tool for exporting Claude Code sessions to styled HTML.

## Features

- Interactive session picker with fuzzy search.
- Lists sessions for current project first, falls back to all projects.
- Exports rendered terminal output to HTML with syntax highlighting.

## Requirements

- [Claude Code](https://claude.ai/claude-code) for session export to ANSI.
- [kitty](https://sw.kovidgoyal.net/kitty/) for capturing ANSI.
- [aha](https://github.com/theZiz/aha) for converting ANSI to HTML.

## Installation

```bash
go build -o capture-claude .
```

## Usage

```bash
# Run from any project directory.
./capture-claude

# Specify output file.
./capture-claude -o session.html
```

## Kitty Configuration

This tool requires kitty's remote control socket.

Either add this to your `~/.config/kitty/kitty.conf`:

```
allow_remote_control yes
listen_on unix:/tmp/kitty-$USER
```

Or start kitty with:

```bash
kitty --listen-on unix:/tmp/kitty-$USER
```

When `listen_on` is configured, kitty automatically sets the `KITTY_LISTEN_ON`
environment variable, which the tool uses to connect to the socket.

## How It Works

1. Parses Claude session files from `~/.claude/projects/`.
2. Displays an interactive picker using Bubble Tea.
3. Connects to kitty via the remote control socket.
4. Launches a kitty window with `claude --resume <session-id>`.
5. Captures the rendered terminal output with ANSI codes.
6. Converts ANSI to HTML using `aha`.
7. Applies custom CSS for light-mode readability.

## Go Dependencies

- [charmbracelet/bubbletea](https://github.com/charmbracelet/bubbletea) - TUI framework.
- [charmbracelet/bubbles](https://github.com/charmbracelet/bubbles) - TUI components.
- [charmbracelet/lipgloss](https://github.com/charmbracelet/lipgloss) - Styling.
