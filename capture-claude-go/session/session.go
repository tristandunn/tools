// Package session provides functionality for discovering and parsing
// Claude Code session files.
package session

import (
	"bufio"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Session represents a Claude session with metadata for display.
type Session struct {
	ID        string
	Path      string
	Timestamp time.Time
	Preview   string
	Project   string
}

// jsonLine represents a single line from a session JSONL file.
type jsonLine struct {
	Type      string    `json:"type"`
	SessionID string    `json:"sessionId"`
	Timestamp time.Time `json:"timestamp"`
	Message   *message  `json:"message"`
	Summary   string    `json:"summary"`
}

// message represents the message content within a session line.
type message struct {
	Role    string `json:"role"`
	Content any    `json:"content"`
}

// errEmptySession indicates a session file with no meaningful content.
var errEmptySession = errors.New("empty session")

// FindSessions returns sessions for the given working directory. If no sessions
// exist for that directory, it returns sessions from all projects. The second
// return value indicates whether results are from all projects.
func FindSessions(cwd string) ([]Session, bool, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, false, err
	}

	projectsDir := filepath.Join(homeDir, ".claude", "projects")
	escapedPath := pathToEscaped(cwd)
	currentProjectDir := filepath.Join(projectsDir, escapedPath)

	sessions, err := findSessionsInDir(currentProjectDir, escapedPath)
	if err == nil && len(sessions) > 0 {
		return sessions, false, nil
	}

	allSessions, err := findAllSessions(projectsDir)
	if err != nil {
		return nil, false, err
	}

	return allSessions, true, nil
}

// pathToEscaped converts a filesystem path to the escaped format used by
// Claude for project directory names.
func pathToEscaped(path string) string {
	return strings.ReplaceAll(path, "/", "-")
}

// escapedToPath converts an escaped project directory name back to the
// original filesystem path.
func escapedToPath(escaped string) string {
	if escaped == "" {
		return ""
	}
	if escaped[0] == '-' {
		escaped = escaped[1:]
	}
	return "/" + strings.ReplaceAll(escaped, "-", "/")
}

// projectDisplayName extracts a human-readable project name from an escaped
// project directory name.
func projectDisplayName(escaped string) string {
	path := escapedToPath(escaped)
	return filepath.Base(path)
}

// findSessionsInDir returns all valid sessions from the specified directory.
func findSessionsInDir(dir, project string) ([]Session, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	var sessions []Session
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		name := entry.Name()
		if !strings.HasSuffix(name, ".jsonl") || strings.HasPrefix(name, "agent-") {
			continue
		}

		path := filepath.Join(dir, name)
		s, err := parseSessionPreview(path, project)
		if err != nil {
			continue
		}
		sessions = append(sessions, s)
	}

	sort.Slice(sessions, func(i, j int) bool {
		return sessions[i].Timestamp.After(sessions[j].Timestamp)
	})

	return sessions, nil
}

// findAllSessions returns sessions from all project directories.
func findAllSessions(projectsDir string) ([]Session, error) {
	entries, err := os.ReadDir(projectsDir)
	if err != nil {
		return nil, err
	}

	var allSessions []Session
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		projectName := entry.Name()
		projectDir := filepath.Join(projectsDir, projectName)
		sessions, err := findSessionsInDir(projectDir, projectName)
		if err != nil {
			continue
		}
		allSessions = append(allSessions, sessions...)
	}

	sort.Slice(allSessions, func(i, j int) bool {
		return allSessions[i].Timestamp.After(allSessions[j].Timestamp)
	})

	return allSessions, nil
}

// parseSessionPreview reads a session file and extracts metadata for display.
// It returns errEmptySession if the file contains no user messages or summary.
func parseSessionPreview(path, project string) (Session, error) {
	file, err := os.Open(path)
	if err != nil {
		return Session{}, err
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		return Session{}, err
	}

	scanner := bufio.NewScanner(file)
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 1024*1024)

	var sessionID string
	var timestamp time.Time
	var preview string
	var summary string

	for scanner.Scan() {
		var line jsonLine
		if err := json.Unmarshal(scanner.Bytes(), &line); err != nil {
			continue
		}

		if line.SessionID != "" && sessionID == "" {
			sessionID = line.SessionID
		}

		if line.Type == "summary" && line.Summary != "" && summary == "" {
			summary = line.Summary
		}

		if line.Type == "user" && line.Message != nil && preview == "" {
			if content, ok := line.Message.Content.(string); ok {
				preview = truncateString(content, 60)
				timestamp = line.Timestamp
			}
		}

		if sessionID != "" && preview != "" {
			break
		}
	}

	if preview == "" && summary != "" {
		preview = truncateString(summary, 60)
	}

	if preview == "" {
		return Session{}, errEmptySession
	}

	if sessionID == "" {
		sessionID = strings.TrimSuffix(filepath.Base(path), ".jsonl")
	}

	if timestamp.IsZero() {
		timestamp = info.ModTime()
	}

	return Session{
		ID:        sessionID,
		Path:      path,
		Timestamp: timestamp,
		Preview:   preview,
		Project:   projectDisplayName(project),
	}, nil
}

// truncateString shortens a string to the specified maximum length, replacing
// newlines with spaces and adding an ellipsis if truncated. It operates on
// runes to avoid breaking multi-byte UTF-8 characters.
func truncateString(s string, maxLen int) string {
	s = strings.ReplaceAll(s, "\n", " ")
	s = strings.TrimSpace(s)

	runes := []rune(s)
	if len(runes) <= maxLen {
		return s
	}
	return string(runes[:maxLen-3]) + "..."
}
