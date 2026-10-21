package relay

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// The tunnel is a persistent outbound WebSocket carrying a small multiplexing
// protocol. Outbound is the whole point: it means Headscale needs no inbound
// port, no port forwarding, and no public IP.
//
// Two kinds of traffic ride it:
//
//   - Ordinary HTTP requests, forwarded whole (request/response).
//   - Raw byte streams for TS2021, which is an HTTP Upgrade the relay cannot
//     interpret. Those arrive as ws_open/ws_data/ws_close and are spliced to a
//     TCP connection against local Headscale.
//
// The relay sees only ciphertext either way.

type tunnelMessage struct {
	Type string          `json:"type"`
	Data json.RawMessage `json:"data,omitempty"`
}

type tunnelRequest struct {
	ID       string            `json:"id"`
	Method   string            `json:"method"`
	URL      string            `json:"url"`
	Headers  map[string]string `json:"headers"`
	Body     *string           `json:"body,omitempty"`
	IsBinary bool              `json:"isBinary,omitempty"`
}

type tunnelResponse struct {
	ID       string            `json:"id"`
	Status   int               `json:"status"`
	Headers  map[string]string `json:"headers"`
	Body     *string           `json:"body,omitempty"`
	IsBinary bool              `json:"isBinary,omitempty"`
}

type wsOpen struct {
	ID      string            `json:"id"`
	URL     string            `json:"url"`
	Headers map[string]string `json:"headers"`
}

type wsData struct {
	ID   string `json:"id"`
	Data string `json:"data"` // base64
}

type wsClose struct {
	ID string `json:"id"`
}

// Tunnel holds one relay connection open and serves whatever arrives.
type Tunnel struct {
	// HeadscaleURL is the local Headscale this forwards to.
	HeadscaleURL string

	conn   *websocket.Conn
	writeM sync.Mutex

	streamsM sync.Mutex
	streams  map[string]net.Conn
}

// Run dials the tunnel and blocks until it drops or ctx is cancelled.
//
// Returning on error rather than reconnecting internally is deliberate: the
// caller owns the backoff policy, and a tunnel that silently reconnects forever
// hides a persistent failure (revoked registration, relay gone) that someone
// needs to see.
func (t *Tunnel) Run(ctx context.Context, tunnelURL string) error {
	dialer := websocket.Dialer{
		HandshakeTimeout: 20 * time.Second,
		// The relay may sit behind a proxy that buffers; no compression keeps
		// the byte stream predictable.
		EnableCompression: false,
	}
	conn, resp, err := dialer.DialContext(ctx, tunnelURL, nil)
	if err != nil {
		if resp != nil {
			return fmt.Errorf("dial tunnel: %w (HTTP %d)", err, resp.StatusCode)
		}
		return fmt.Errorf("dial tunnel: %w", err)
	}
	defer conn.Close()

	t.conn = conn
	t.streams = make(map[string]net.Conn)
	defer t.closeAllStreams()

	log.Printf("[relay] tunnel connected")

	// Keepalive. Idle WebSockets are killed by intermediaries within a couple
	// of minutes, and a Headscale that nobody has contacted recently is exactly
	// the state we need to survive.
	pingCtx, stopPing := context.WithCancel(ctx)
	defer stopPing()
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-pingCtx.Done():
				return
			case <-ticker.C:
				if err := t.send(tunnelMessage{Type: "ping"}); err != nil {
					return
				}
			}
		}
	}()

	// Reading stops when ctx is cancelled: the read below blocks, so closing the
	// connection is what unblocks it.
	go func() {
		<-ctx.Done()
		conn.Close()
	}()

	for {
		var msg tunnelMessage
		if err := conn.ReadJSON(&msg); err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			return fmt.Errorf("tunnel read: %w", err)
		}

		switch msg.Type {
		case "request":
			go t.handleRequest(msg.Data)
		case "ws_open":
			go t.handleStreamOpen(msg.Data)
		case "ws_data":
			t.handleStreamData(msg.Data)
		case "ws_close":
			t.handleStreamClose(msg.Data)
		case "ping":
			_ = t.send(tunnelMessage{Type: "pong"})
		case "pong":
			// keepalive reply
		default:
			log.Printf("[relay] unknown message type %q", msg.Type)
		}
	}
}

func (t *Tunnel) send(msg tunnelMessage) error {
	t.writeM.Lock()
	defer t.writeM.Unlock()
	return t.conn.WriteJSON(msg)
}

func (t *Tunnel) sendTyped(typ string, payload any) error {
	raw, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	return t.send(tunnelMessage{Type: typ, Data: raw})
}

// handleRequest forwards an ordinary HTTP request to local Headscale.
func (t *Tunnel) handleRequest(data json.RawMessage) {
	var req tunnelRequest
	if err := json.Unmarshal(data, &req); err != nil {
		log.Printf("[relay] bad request payload: %v", err)
		return
	}

	resp, err := t.forward(req)
	if err != nil {
		log.Printf("[relay] forward %s %s: %v", req.Method, req.URL, err)
		body := "Bad Gateway"
		resp = &tunnelResponse{
			ID:      req.ID,
			Status:  http.StatusBadGateway,
			Headers: map[string]string{"Content-Type": "text/plain"},
			Body:    &body,
		}
	}
	if err := t.sendTyped("response", resp); err != nil {
		log.Printf("[relay] send response: %v", err)
	}
}

func (t *Tunnel) forward(req tunnelRequest) (*tunnelResponse, error) {
	var body io.Reader
	if req.Body != nil {
		if req.IsBinary {
			decoded, err := base64.StdEncoding.DecodeString(*req.Body)
			if err != nil {
				return nil, fmt.Errorf("decode body: %w", err)
			}
			body = strings.NewReader(string(decoded))
		} else {
			body = strings.NewReader(*req.Body)
		}
	}

	url := strings.TrimRight(t.HeadscaleURL, "/") + req.URL
	httpReq, err := http.NewRequest(req.Method, url, body)
	if err != nil {
		return nil, err
	}
	for k, v := range req.Headers {
		// Host must be set on the struct field; setting the header is ignored.
		if strings.EqualFold(k, "host") {
			httpReq.Host = v
			continue
		}
		httpReq.Header.Set(k, v)
	}

	client := &http.Client{Timeout: 30 * time.Second}
	httpResp, err := client.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer httpResp.Body.Close()

	raw, err := io.ReadAll(io.LimitReader(httpResp.Body, 16<<20))
	if err != nil {
		return nil, err
	}

	headers := make(map[string]string, len(httpResp.Header))
	for k := range httpResp.Header {
		headers[k] = httpResp.Header.Get(k)
	}

	// Base64 anything that is not valid UTF-8 text, so binary protobuf bodies
	// survive the JSON envelope intact.
	encoded := string(raw)
	isBinary := !isPrintableUTF8(raw)
	if isBinary {
		encoded = base64.StdEncoding.EncodeToString(raw)
	}

	return &tunnelResponse{
		ID:       req.ID,
		Status:   httpResp.StatusCode,
		Headers:  headers,
		Body:     &encoded,
		IsBinary: isBinary,
	}, nil
}

// handleStreamOpen splices a raw byte stream to local Headscale.
//
// This is the TS2021 control channel. The relay cannot interpret it, so it
// hands us the bytes and we act as a plain TCP proxy.
func (t *Tunnel) handleStreamOpen(data json.RawMessage) {
	var open wsOpen
	if err := json.Unmarshal(data, &open); err != nil {
		log.Printf("[relay] bad ws_open: %v", err)
		return
	}

	addr, err := hostPortFromURL(t.HeadscaleURL)
	if err != nil {
		log.Printf("[relay] bad headscale URL: %v", err)
		_ = t.sendTyped("ws_close", wsClose{ID: open.ID})
		return
	}

	conn, err := net.DialTimeout("tcp", addr, 10*time.Second)
	if err != nil {
		log.Printf("[relay] dial headscale for stream: %v", err)
		_ = t.sendTyped("ws_close", wsClose{ID: open.ID})
		return
	}

	t.streamsM.Lock()
	t.streams[open.ID] = conn
	t.streamsM.Unlock()

	// Replay the upgrade request that opened this stream, so Headscale sees the
	// same handshake the client sent.
	var head strings.Builder
	fmt.Fprintf(&head, "GET %s HTTP/1.1\r\n", open.URL)
	if _, ok := open.Headers["Host"]; !ok {
		fmt.Fprintf(&head, "Host: %s\r\n", addr)
	}
	for k, v := range open.Headers {
		fmt.Fprintf(&head, "%s: %s\r\n", k, v)
	}
	head.WriteString("\r\n")
	if _, err := conn.Write([]byte(head.String())); err != nil {
		log.Printf("[relay] write upgrade head: %v", err)
		t.closeStream(open.ID)
		return
	}

	// Pump Headscale -> relay until the connection ends.
	go func() {
		buf := make([]byte, 32<<10)
		for {
			n, err := conn.Read(buf)
			if n > 0 {
				if sendErr := t.sendTyped("ws_data", wsData{
					ID:   open.ID,
					Data: base64.StdEncoding.EncodeToString(buf[:n]),
				}); sendErr != nil {
					break
				}
			}
			if err != nil {
				break
			}
		}
		t.closeStream(open.ID)
		_ = t.sendTyped("ws_close", wsClose{ID: open.ID})
	}()
}

func (t *Tunnel) handleStreamData(data json.RawMessage) {
	var msg wsData
	if err := json.Unmarshal(data, &msg); err != nil {
		return
	}
	t.streamsM.Lock()
	conn := t.streams[msg.ID]
	t.streamsM.Unlock()
	if conn == nil {
		return
	}
	raw, err := base64.StdEncoding.DecodeString(msg.Data)
	if err != nil {
		return
	}
	if _, err := conn.Write(raw); err != nil {
		t.closeStream(msg.ID)
	}
}

func (t *Tunnel) handleStreamClose(data json.RawMessage) {
	var msg wsClose
	if err := json.Unmarshal(data, &msg); err != nil {
		return
	}
	t.closeStream(msg.ID)
}

func (t *Tunnel) closeStream(id string) {
	t.streamsM.Lock()
	conn := t.streams[id]
	delete(t.streams, id)
	t.streamsM.Unlock()
	if conn != nil {
		conn.Close()
	}
}

func (t *Tunnel) closeAllStreams() {
	t.streamsM.Lock()
	for id, conn := range t.streams {
		conn.Close()
		delete(t.streams, id)
	}
	t.streamsM.Unlock()
}

func hostPortFromURL(raw string) (string, error) {
	trimmed := strings.TrimPrefix(strings.TrimPrefix(raw, "http://"), "https://")
	trimmed = strings.TrimRight(trimmed, "/")
	if i := strings.Index(trimmed, "/"); i >= 0 {
		trimmed = trimmed[:i]
	}
	if trimmed == "" {
		return "", fmt.Errorf("no host in %q", raw)
	}
	if !strings.Contains(trimmed, ":") {
		if strings.HasPrefix(raw, "https://") {
			return trimmed + ":443", nil
		}
		return trimmed + ":80", nil
	}
	return trimmed, nil
}

// isPrintableUTF8 reports whether a body can ride the JSON envelope as text.
func isPrintableUTF8(b []byte) bool {
	for _, c := range b {
		// Control characters other than tab/newline/carriage-return mean this
		// is binary as far as JSON is concerned.
		if c < 0x09 || (c > 0x0d && c < 0x20) {
			return false
		}
	}
	return true
}
