// Package export provides kitty terminal remote control client functionality.
package export

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"time"
)

const (
	escapeStart = "\x1bP@kitty-cmd"
	escapeEnd   = "\x1b\\"
)

// kittyVersion is the protocol version to send with commands.
var kittyVersion = []int{0, 14, 2}

// Client communicates with kitty via the remote control protocol.
type Client struct {
	conn net.Conn
}

// command represents a kitty remote control command.
type command struct {
	Cmd        string `json:"cmd"`
	Version    []int  `json:"version"`
	NoResponse bool   `json:"no_response,omitempty"`
	Payload    any    `json:"payload,omitempty"`
}

// response represents a kitty remote control response.
type response struct {
	Ok    bool   `json:"ok"`
	Data  string `json:"data,omitempty"`
	Error string `json:"error,omitempty"`
}

// NewClient creates a new kitty remote control client by connecting to the
// kitty socket. It looks for the socket path in KITTY_LISTEN_ON environment
// variable.
func NewClient() (*Client, error) {
	socketPath := os.Getenv("KITTY_LISTEN_ON")
	if socketPath == "" {
		return nil, errors.New("KITTY_LISTEN_ON not set; not running in kitty or remote control not enabled")
	}

	// Handle unix: prefix
	socketPath = strings.TrimPrefix(socketPath, "unix:")

	conn, err := net.DialTimeout("unix", socketPath, 5*time.Second)
	if err != nil {
		return nil, fmt.Errorf("connecting to kitty socket: %w", err)
	}

	return &Client{conn: conn}, nil
}

// Close closes the connection to kitty.
func (c *Client) Close() error {
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}

// sendCommand sends a command to kitty and returns the response.
func (c *Client) sendCommand(cmd string, payload interface{}) (*response, error) {
	cmdObj := command{
		Cmd:     cmd,
		Version: kittyVersion,
		Payload: payload,
	}

	jsonBytes, err := json.Marshal(cmdObj)
	if err != nil {
		return nil, fmt.Errorf("marshaling command: %w", err)
	}

	// Send: <ESC>P@kitty-cmd{json}<ESC>\
	msg := escapeStart + string(jsonBytes) + escapeEnd
	if _, err := c.conn.Write([]byte(msg)); err != nil {
		return nil, fmt.Errorf("writing command: %w", err)
	}

	// Read response with timeout
	c.conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	defer c.conn.SetReadDeadline(time.Time{})
	reader := bufio.NewReader(c.conn)

	// Response format: <ESC>P@kitty-cmd{json}<ESC>\
	// Read until we find the escape end sequence
	var respData strings.Builder
	for {
		b, err := reader.ReadByte()
		if err != nil {
			return nil, fmt.Errorf("reading response: %w", err)
		}
		respData.WriteByte(b)

		// Check for escape end
		if strings.HasSuffix(respData.String(), escapeEnd) {
			break
		}
	}

	// Extract JSON from response
	raw := respData.String()
	if !strings.HasPrefix(raw, escapeStart) {
		return nil, fmt.Errorf("invalid response format: missing start sequence")
	}

	jsonStr := strings.TrimPrefix(raw, escapeStart)
	jsonStr = strings.TrimSuffix(jsonStr, escapeEnd)

	var resp response
	if err := json.Unmarshal([]byte(jsonStr), &resp); err != nil {
		return nil, fmt.Errorf("parsing response: %w", err)
	}

	if !resp.Ok {
		return nil, fmt.Errorf("kitty error: %s", resp.Error)
	}

	return &resp, nil
}

// launchPayload is the payload for the launch command.
type launchPayload struct {
	Args        []string `json:"args"`
	Cwd         string   `json:"cwd,omitempty"`
	WindowTitle string   `json:"window_title,omitempty"`
	Type        string   `json:"type,omitempty"`
	KeepFocus   bool     `json:"keep_focus,omitempty"`
}

// Launch starts a new window with the specified command.
func (c *Client) Launch(args []string, cwd, title, windowType string, keepFocus bool) (string, error) {
	payload := launchPayload{
		Args:        args,
		Cwd:         cwd,
		WindowTitle: title,
		Type:        windowType,
		KeepFocus:   keepFocus,
	}

	resp, err := c.sendCommand("launch", payload)
	if err != nil {
		return "", err
	}

	return strings.TrimSpace(resp.Data), nil
}

// resizePayload is the payload for the resize-os-window command.
type resizePayload struct {
	Match string `json:"match"`
	Width int    `json:"width,omitempty"`
	Unit  string `json:"unit,omitempty"`
}

// ResizeWindow resizes a kitty window.
func (c *Client) ResizeWindow(windowID string, width int, unit string) error {
	payload := resizePayload{
		Match: "id:" + windowID,
		Width: width,
		Unit:  unit,
	}

	_, err := c.sendCommand("resize-os-window", payload)
	return err
}

// getTextPayload is the payload for the get-text command.
type getTextPayload struct {
	Match  string `json:"match"`
	Extent string `json:"extent,omitempty"`
	Ansi   bool   `json:"ansi,omitempty"`
}

// GetText retrieves text content from a kitty window.
func (c *Client) GetText(windowID, extent string, ansi bool) (string, error) {
	payload := getTextPayload{
		Match:  "id:" + windowID,
		Extent: extent,
		Ansi:   ansi,
	}

	resp, err := c.sendCommand("get-text", payload)
	if err != nil {
		return "", err
	}

	return resp.Data, nil
}

// closePayload is the payload for the close-window command.
type closePayload struct {
	Match string `json:"match"`
}

// CloseWindow closes a kitty window.
func (c *Client) CloseWindow(windowID string) error {
	payload := closePayload{
		Match: "id:" + windowID,
	}

	_, err := c.sendCommand("close-window", payload)
	return err
}

// IsAvailable returns true if native kitty protocol is available.
func IsAvailable() bool {
	return os.Getenv("KITTY_LISTEN_ON") != ""
}
