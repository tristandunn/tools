// Package export handles exporting Claude sessions to HTML using kitty
// terminal's remote control protocol.
package export

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// customCSS defines the styling for exported HTML documents (aha-compatible).
const customCSS = `<style>
body {
  background: #FFFFFF;
  color: #000000;
  font-family: "Monaspace Neon Var", ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  line-height: 1.2;
}
.wrapper {
  display: inline-block;
  text-align: left;
}
body {
  text-align: center;
}
pre { margin: 0; }
.ef0, .black { color: #000000; }
.ef1, .red { color: #A00000; }
.ef2, .green { color: #00A000; }
.ef3, .olive, .yellow { color: #AA5500; }
.ef4, .navy, .blue { color: #0000AA; }
.ef5, .purple, .magenta { color: #AA00AA; }
.ef6, .teal, .cyan { color: #00AAAA; }
.ef7, .silver, .white { color: #AAAAAA; }
.ef8, .gray, .dimgray { color: #555555; }
.ef9 { color: #FF5555; }
.ef10 { color: #55FF55; }
.ef11 { color: #FFFF55; }
.ef12 { color: #5555FF; }
.ef13 { color: #FF55FF; }
.ef14 { color: #55FFFF; }
.ef15 { color: #FFFFFF; }
.eb0 { background-color: #000000; }
.eb1 { background-color: #FFDDDD; }
.eb2 { background-color: #DDFFDD; }
.eb3 { background-color: #FFFFDD; }
.eb4 { background-color: #DDDDFF; }
.eb5 { background-color: #FFDDFF; }
.eb6 { background-color: #DDFFFF; }
.eb7 { background-color: #EEEEEE; }
.eb8 { background-color: #555555; }
.eb9 { background-color: #FFDDDD; }
.eb10 { background-color: #DDFFDD; }
.eb11 { background-color: #FFFFDD; }
.eb12 { background-color: #DDDDFF; }
.eb13 { background-color: #FFDDFF; }
.eb14 { background-color: #DDFFFF; }
.eb15 { background-color: #FFFFFF; }
.bold { font-weight: bold; }
.italic { font-style: italic; }
.underline { text-decoration: underline; }
</style>`

// colorReplacements maps dark terminal colors to light-background equivalents.
var colorReplacements = []struct{ old, new string }{
	{"color:#ffffff;background-color:#7a2936", "color:#000;background-color:#FDD"},
	{"color:#ffffff;background-color:#225c2b", "color:#000;background-color:#DFD"},
	{"color:#ffffff;background-color:#b3596b", "color:#000;background-color:#FDD"},
	{"color:#ffffff;background-color:#38a660", "color:#000;background-color:#DFD"},
	{"background-color:#7a2936", "background-color:#FDD"},
	{"background-color:#225c2b", "background-color:#DFD"},
	{"color:#ffffff;background-color:#373737", "color:#000;background-color:#EEE"},
}

// stylePattern matches aha's default style block for replacement.
var stylePattern = regexp.MustCompile(`(?s)<style[^>]*>.*?</style>`)

// promptPattern matches the vim mode indicator at the bottom of Claude's interface.
var promptPattern = regexp.MustCompile(`-- INSERT --|-- NORMAL --`)

// ansiPattern matches ANSI escape sequences for stripping.
var ansiPattern = regexp.MustCompile(`\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[()][AB012]`)

// ExportSession exports a Claude session to an HTML file using the native
// kitty remote control protocol.
func ExportSession(sessionID, project, cwd, outputFile string) error {
	client, err := NewClient()
	if err != nil {
		return err
	}
	defer client.Close()

	// Launch window with Claude session
	args := []string{"claude", "--resume", sessionID}
	windowID, err := client.Launch(args, cwd, "claude-export", "os-window", true)
	if err != nil {
		return fmt.Errorf("launching window: %w", err)
	}
	defer client.CloseWindow(windowID)

	// Resize window to 100 columns
	if err := client.ResizeWindow(windowID, 100, "cells"); err != nil {
		return fmt.Errorf("resizing window: %w", err)
	}

	// Allow time for Claude to render the session.
	const renderWaitTime = 2 * time.Second
	time.Sleep(renderWaitTime)

	// Get text with ANSI codes
	content, err := client.GetText(windowID, "all", true)
	if err != nil {
		return fmt.Errorf("getting text: %w", err)
	}

	// Strip prompt and convert to HTML
	content = stripPromptFromContent(content)
	title := project + " - Claude Code"
	html, err := convertANSIToHTML(content, title)
	if err != nil {
		return fmt.Errorf("converting to HTML: %w", err)
	}

	return os.WriteFile(outputFile, []byte(html), 0o644)
}

// convertANSIToHTML converts ANSI-encoded text to styled HTML using aha.
func convertANSIToHTML(content, title string) (string, error) {
	cmd := exec.Command("aha", "--stylesheet", "--title", title)
	cmd.Stdin = strings.NewReader(content)

	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("running aha: %w", err)
	}

	html := string(output)

	// Replace aha's default style block with custom CSS
	html = stylePattern.ReplaceAllString(html, customCSS)

	// Apply color replacements for better light-mode readability
	for _, r := range colorReplacements {
		html = strings.ReplaceAll(html, r.old, r.new)
	}

	// Remove empty class attributes
	html = strings.ReplaceAll(html, ` class=""`, "")

	// Wrap content in a centered container
	html = strings.Replace(html, "<body>", `<body><div class="wrapper">`, 1)
	html = strings.Replace(html, "</body>", "</div></body>", 1)

	return html, nil
}

// stripPromptFromContent removes the input prompt area from captured text.
func stripPromptFromContent(content string) string {
	lines := strings.Split(content, "\n")

	// Find the last line containing the mode indicator.
	promptLine := -1
	for i, line := range lines {
		if promptPattern.MatchString(line) {
			promptLine = i
		}
	}

	if promptLine == -1 {
		return content
	}

	// Cut from the promptLine back to include the separator and input lines.
	// The prompt area is typically:
	//   ─────────────────── (separator)
	//   > [input text]
	//   ─────────────────── (separator)
	//   -- INSERT -- or -- NORMAL --
	//
	// We want to remove everything from the first separator onwards.
	// Search backwards to find where the prompt area starts.
	cutLine := promptLine
	for i := promptLine; i >= 0 && i >= promptLine-10; i-- {
		stripped := ansiPattern.ReplaceAllString(lines[i], "")
		trimmed := strings.TrimSpace(stripped)
		// Check if line contains separator dashes (not just starts with)
		// The separator may have leading spaces or other characters
		if strings.Contains(trimmed, "─────────────────────") {
			cutLine = i
		}
	}

	lines = lines[:cutLine]
	return strings.Join(lines, "\n")
}

// DefaultOutputPath returns the default path for the exported HTML file.
func DefaultOutputPath() string {
	cwd, err := os.Getwd()
	if err != nil {
		cwd = "."
	}
	timestamp := time.Now().Format("20060102-150405")
	return filepath.Join(cwd, fmt.Sprintf("claude-session-%s.html", timestamp))
}

// CheckDependencies verifies that required external tools are available.
func CheckDependencies() error {
	// Check for aha
	if _, err := exec.LookPath("aha"); err != nil {
		return fmt.Errorf("aha not found in PATH")
	}

	// Check for claude
	if _, err := exec.LookPath("claude"); err != nil {
		return fmt.Errorf("claude not found in PATH")
	}

	// Check for kitty socket
	if !IsAvailable() {
		return fmt.Errorf("kitty remote control not available (KITTY_LISTEN_ON not set)")
	}

	return nil
}
