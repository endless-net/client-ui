//go:build windows

package serviceemulator

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"testing"
	"time"
)

func TestNamedPipeServerRoundTrip(t *testing.T) {
	engine := newTestEngine(t, DefaultScenario(), nil)
	pipePath := fmt.Sprintf(`\\.\pipe\endlessnet-emulator-go-test-%d`, os.Getpid())
	server := &Server{PipePath: pipePath, Engine: engine, Ready: make(chan struct{})}
	ctx, cancel := context.WithCancel(context.Background())
	errCh := make(chan error, 1)
	go func() { errCh <- server.Serve(ctx) }()
	select {
	case <-server.Ready:
	case err := <-errCh:
		t.Fatalf("server start: %v", err)
	case <-time.After(5 * time.Second):
		t.Fatal("server readiness timed out")
	}
	t.Cleanup(func() {
		cancel()
		select {
		case err := <-errCh:
			if err != nil {
				t.Errorf("server stop: %v", err)
			}
		case <-time.After(5 * time.Second):
			t.Error("server stop timed out")
		}
	})

	status := pipeRequest(t, pipePath, http.MethodGet, "/status", nil)
	if status.StatusCode != http.StatusOK || status.Payload["state"] != "Connected" {
		t.Fatalf("initial status = %#v", status)
	}
	disconnected := pipeRequest(t, pipePath, http.MethodPost, "/disconnect", []byte(`{}`))
	if disconnected.StatusCode != http.StatusOK || disconnected.Payload["state"] != "Disconnected" {
		t.Fatalf("disconnect response = %#v", disconnected)
	}
	status = pipeRequest(t, pipePath, http.MethodGet, "/status", nil)
	if status.Payload["state"] != "Disconnected" {
		t.Fatalf("updated status = %#v", status)
	}

	missingHeaders := pipeRequestWithoutIPCHeaders(t, pipePath, http.MethodGet, "/status", nil)
	if missingHeaders.StatusCode != http.StatusUpgradeRequired || missingHeaders.Payload["error_code"] != "ipc_version_required" {
		t.Fatalf("missing IPC headers response = %#v", missingHeaders)
	}
	version2Headers := fmt.Sprintf(
		"%s: %s\r\n%s: 2\r\n%s: 2\r\n",
		IPCProtocolHeader,
		IPCProtocol,
		IPCVersionHeader,
		IPCMinVersionHeader,
	)
	version2 := pipeRequestWithRawIPCHeaders(t, pipePath, http.MethodGet, "/status", nil, version2Headers)
	if version2.StatusCode != http.StatusUpgradeRequired || version2.Payload["error_code"] != "ipc_version_unsupported" {
		t.Fatalf("IPC version 2 response = %#v", version2)
	}
}

type pipeResponse struct {
	StatusCode int
	Payload    map[string]any
}

func pipeRequest(t *testing.T, pipePath, method, target string, body []byte) pipeResponse {
	return pipeRequestWithHeaders(t, pipePath, method, target, body, true)
}

func pipeRequestWithoutIPCHeaders(t *testing.T, pipePath, method, target string, body []byte) pipeResponse {
	return pipeRequestWithHeaders(t, pipePath, method, target, body, false)
}

func pipeRequestWithHeaders(t *testing.T, pipePath, method, target string, body []byte, includeIPCHeaders bool) pipeResponse {
	t.Helper()
	ipcHeaders := ""
	if includeIPCHeaders {
		ipcHeaders = fmt.Sprintf("%s: %s\r\n%s: %d\r\n%s: %d\r\n", IPCProtocolHeader, IPCProtocol, IPCVersionHeader, IPCVersion, IPCMinVersionHeader, IPCVersion)
	}
	return pipeRequestWithRawIPCHeaders(t, pipePath, method, target, body, ipcHeaders)
}

func pipeRequestWithRawIPCHeaders(t *testing.T, pipePath, method, target string, body []byte, ipcHeaders string) pipeResponse {
	t.Helper()
	file, err := os.OpenFile(pipePath, os.O_RDWR, 0)
	if err != nil {
		t.Fatalf("open pipe: %v", err)
	}
	request := fmt.Sprintf(
		"%s %s HTTP/1.1\r\nHost: endlessnet.local\r\nContent-Type: application/json\r\n%sContent-Length: %d\r\nConnection: close\r\n\r\n",
		method,
		target,
		ipcHeaders,
		len(body),
	)
	if _, err := io.WriteString(file, request); err != nil {
		file.Close()
		t.Fatalf("write request: %v", err)
	}
	if _, err := file.Write(body); err != nil {
		file.Close()
		t.Fatalf("write body: %v", err)
	}
	raw, err := io.ReadAll(file)
	file.Close()
	if err != nil && len(raw) == 0 {
		t.Fatalf("read response: %v", err)
	}
	httpRequest, _ := http.NewRequest(method, "http://endlessnet.local"+target, bytes.NewReader(body))
	response, err := http.ReadResponse(bufio.NewReader(bytes.NewReader(raw)), httpRequest)
	if err != nil {
		t.Fatalf("parse response %q: %v", raw, err)
	}
	defer response.Body.Close()
	var payload map[string]any
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("decode payload: %v", err)
	}
	return pipeResponse{StatusCode: response.StatusCode, Payload: payload}
}
