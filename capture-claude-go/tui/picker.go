// Package tui provides an interactive terminal interface for selecting
// Claude sessions using the Bubble Tea framework.
package tui

import (
	"fmt"
	"io"
	"strings"
	"time"

	"capture-claude-go/session"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Styles for the session picker interface.
var (
	titleStyle        = lipgloss.NewStyle().MarginLeft(2)
	itemStyle         = lipgloss.NewStyle().PaddingLeft(4)
	selectedItemStyle = lipgloss.NewStyle().PaddingLeft(2).Foreground(lipgloss.Color("170"))
	paginationStyle   = list.DefaultStyles().PaginationStyle.PaddingLeft(4)
	helpStyle         = list.DefaultStyles().HelpStyle.PaddingLeft(4).PaddingBottom(1)
	dimStyle          = lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
	projectStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("39"))
)

// sessionItem wraps a Session for use in the list component.
type sessionItem struct {
	session session.Session
}

// FilterValue returns the string used for fuzzy filtering.
func (i sessionItem) FilterValue() string {
	return i.session.Preview
}

// itemDelegate handles rendering of individual list items.
type itemDelegate struct {
	showProject   bool
	maxProjectLen int
}

// Height returns the number of lines each item occupies.
func (d itemDelegate) Height() int { return 1 }

// Spacing returns the number of blank lines between items.
func (d itemDelegate) Spacing() int { return 0 }

// Update handles item-level events.
func (d itemDelegate) Update(_ tea.Msg, _ *list.Model) tea.Cmd { return nil }

// Render draws a single list item to the writer.
func (d itemDelegate) Render(w io.Writer, m list.Model, index int, listItem list.Item) {
	i, ok := listItem.(sessionItem)
	if !ok {
		return
	}

	ts := formatTimestamp(i.session.Timestamp)

	var str string
	if d.showProject {
		project := fmt.Sprintf("%-*s", d.maxProjectLen, i.session.Project)
		str = fmt.Sprintf("%s  %s  %s",
			dimStyle.Render(ts),
			projectStyle.Render(project),
			i.session.Preview)
	} else {
		str = fmt.Sprintf("%s  %s", dimStyle.Render(ts), i.session.Preview)
	}

	fn := itemStyle.Render
	if index == m.Index() {
		fn = func(s ...string) string {
			return selectedItemStyle.Render("> " + strings.Join(s, " "))
		}
	}

	fmt.Fprint(w, fn(str))
}

// formatTimestamp returns a fixed-width timestamp string for consistent alignment.
func formatTimestamp(t time.Time) string {
	t = t.Local()
	hour := t.Hour() % 12
	if hour == 0 {
		hour = 12
	}
	return fmt.Sprintf("%s %2d, %2d:%02d %s",
		t.Format("Jan"), t.Day(), hour, t.Minute(), t.Format("PM"))
}

// model is the Bubble Tea model for the session picker.
type model struct {
	list     list.Model
	selected *session.Session
	quitting bool
}

// Init returns the initial command for the model.
func (m model) Init() tea.Cmd {
	return nil
}

// Update handles messages and updates the model state.
func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.list.SetWidth(msg.Width)
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c", "esc":
			m.quitting = true
			return m, tea.Quit

		case "enter":
			if i, ok := m.list.SelectedItem().(sessionItem); ok {
				m.selected = &i.session
			}
			return m, tea.Quit
		}
	}

	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

// View renders the current state of the model.
func (m model) View() string {
	if m.quitting {
		return ""
	}
	return "\n" + m.list.View()
}

// PickSession displays an interactive picker for selecting a session.
// It returns the selected session, or nil if the user cancelled.
func PickSession(sessions []session.Session, showProject bool) (*session.Session, error) {
	maxProjectLen := 0
	if showProject {
		for _, s := range sessions {
			if len(s.Project) > maxProjectLen {
				maxProjectLen = len(s.Project)
			}
		}
	}

	items := make([]list.Item, len(sessions))
	for i, s := range sessions {
		items[i] = sessionItem{session: s}
	}

	const (
		defaultWidth = 100
		listHeight   = 14
	)

	delegate := itemDelegate{
		showProject:   showProject,
		maxProjectLen: maxProjectLen,
	}
	l := list.New(items, delegate, defaultWidth, listHeight)

	if showProject {
		l.Title = "Select a session (all projects)"
	} else {
		l.Title = "Select a session"
	}

	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(true)
	l.Styles.Title = titleStyle
	l.Styles.PaginationStyle = paginationStyle
	l.Styles.HelpStyle = helpStyle

	p := tea.NewProgram(model{list: l}, tea.WithAltScreen())
	finalModel, err := p.Run()
	if err != nil {
		return nil, err
	}

	if fm, ok := finalModel.(model); ok {
		return fm.selected, nil
	}

	return nil, nil
}
