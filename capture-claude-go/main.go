// Command capture-claude exports Claude Code sessions to styled HTML.
//
// Usage:
//
//	capture-claude [-o output.html]
//
// The command displays an interactive picker to select a session, then
// exports it using kitty terminal's remote control and the aha ANSI-to-HTML
// converter.
package main

import (
	"flag"
	"fmt"
	"os"

	"capture-claude-go/export"
	"capture-claude-go/session"
	"capture-claude-go/tui"
)

func main() {
	outputFile := flag.String("o", "", "Output HTML file path")
	flag.Parse()

	if err := export.CheckDependencies(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	cwd, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error getting working directory: %v\n", err)
		os.Exit(1)
	}

	sessions, showAllProjects, err := session.FindSessions(cwd)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error finding sessions: %v\n", err)
		os.Exit(1)
	}

	if len(sessions) == 0 {
		fmt.Println("No sessions found.")
		os.Exit(0)
	}

	selected, err := tui.PickSession(sessions, showAllProjects)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error showing picker: %v\n", err)
		os.Exit(1)
	}

	if selected == nil {
		os.Exit(0)
	}

	output := *outputFile
	if output == "" {
		output = export.DefaultOutputPath()
	}

	fmt.Printf("Exporting session: %s\n", selected.Preview)
	if err := export.ExportSession(selected.ID, selected.Project, cwd, output); err != nil {
		fmt.Fprintf(os.Stderr, "Error exporting session: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Exported to: %s\n", output)
}
