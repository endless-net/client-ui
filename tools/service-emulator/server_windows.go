//go:build windows

package serviceemulator

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/sys/windows"
)

const (
	pipeBufferBytes  = 64 * 1024
	maxPipeInstances = 64
)

func serveNamedPipe(ctx context.Context, server *Server) error {
	if !strings.HasPrefix(server.PipePath, `\\.\pipe\`) || len(server.PipePath) <= len(`\\.\pipe\`) {
		return fmt.Errorf("pipe path must be a local Windows named pipe: %q", server.PipePath)
	}
	path, err := windows.UTF16PtrFromString(server.PipePath)
	if err != nil {
		return fmt.Errorf("encode pipe path: %w", err)
	}

	var readyOnce sync.Once
	var workers sync.WaitGroup
	go wakeAcceptOnCancellation(ctx, server.PipePath)

	for {
		handle, createErr := windows.CreateNamedPipe(
			path,
			windows.PIPE_ACCESS_DUPLEX,
			windows.PIPE_TYPE_BYTE|windows.PIPE_READMODE_BYTE|windows.PIPE_WAIT|windows.PIPE_REJECT_REMOTE_CLIENTS,
			maxPipeInstances,
			pipeBufferBytes,
			pipeBufferBytes,
			0,
			nil,
		)
		if createErr != nil {
			workers.Wait()
			return fmt.Errorf("create named pipe %q: %w", server.PipePath, createErr)
		}
		readyOnce.Do(func() { close(server.Ready) })

		connectErr := windows.ConnectNamedPipe(handle, nil)
		if connectErr != nil && !errors.Is(connectErr, windows.ERROR_PIPE_CONNECTED) {
			windows.CloseHandle(handle)
			if ctx.Err() != nil {
				workers.Wait()
				return nil
			}
			workers.Wait()
			return fmt.Errorf("accept named pipe connection: %w", connectErr)
		}
		if ctx.Err() != nil {
			windows.DisconnectNamedPipe(handle)
			windows.CloseHandle(handle)
			workers.Wait()
			return nil
		}

		workers.Add(1)
		go func() {
			defer workers.Done()
			servePipeConnection(server, handle)
		}()
	}
}

func wakeAcceptOnCancellation(ctx context.Context, pipePath string) {
	<-ctx.Done()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		file, err := os.OpenFile(pipePath, os.O_RDWR, 0)
		if err == nil {
			file.Close()
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func servePipeConnection(server *Server, handle windows.Handle) {
	file := os.NewFile(uintptr(handle), server.PipePath)
	if file == nil {
		windows.DisconnectNamedPipe(handle)
		windows.CloseHandle(handle)
		return
	}
	defer func() {
		windows.FlushFileBuffers(handle)
		windows.DisconnectNamedPipe(handle)
		file.Close()
	}()

	request, err := http.ReadRequest(bufio.NewReaderSize(file, pipeBufferBytes))
	if err != nil {
		writeResult(file, errorResult(http.StatusBadRequest, "invalid_json", "invalid local HTTP request"))
		return
	}
	defer request.Body.Close()
	if result := validateIPCRequestHeaders(request.Header); result != nil {
		writeResult(file, *result)
		return
	}
	if server.RequestStarted != nil {
		server.RequestStarted()
	}
	body, err := io.ReadAll(io.LimitReader(request.Body, server.MaxBodyBytes+1))
	if err != nil {
		writeResult(file, errorResult(http.StatusBadRequest, "invalid_json", "cannot read request body"))
		return
	}
	if int64(len(body)) > server.MaxBodyBytes {
		writeResult(file, errorResult(http.StatusRequestEntityTooLarge, "request_too_large", "IPC request body is too large"))
		return
	}

	result := server.Engine.Handle(request.Method, request.URL.RequestURI(), body)
	if result.CloseConnection {
		return
	}
	if result.Delay > 0 {
		time.Sleep(result.Delay)
	}
	writeResult(file, result)
}

func validateIPCRequestHeaders(headers http.Header) *Result {
	protocolValues := headers.Values(IPCProtocolHeader)
	versionValues := headers.Values(IPCVersionHeader)
	minimumValues := headers.Values(IPCMinVersionHeader)
	if len(protocolValues) == 0 || len(versionValues) == 0 || len(minimumValues) == 0 {
		result := errorResult(http.StatusUpgradeRequired, "ipc_version_required", "IPC protocol and version range headers are required")
		return &result
	}
	if len(protocolValues) != 1 || strings.TrimSpace(protocolValues[0]) != IPCProtocol {
		result := errorResult(http.StatusUpgradeRequired, "ipc_protocol_unsupported", "unsupported IPC protocol")
		return &result
	}
	if len(versionValues) != 1 || len(minimumValues) != 1 {
		result := errorResult(http.StatusBadRequest, "invalid_ipc_version_range", "IPC version headers must each occur exactly once")
		return &result
	}
	current, currentErr := strconv.Atoi(strings.TrimSpace(versionValues[0]))
	minimum, minimumErr := strconv.Atoi(strings.TrimSpace(minimumValues[0]))
	if currentErr != nil || minimumErr != nil || current <= 0 || minimum <= 0 || minimum > current {
		result := errorResult(http.StatusBadRequest, "invalid_ipc_version_range", "IPC version range is invalid")
		return &result
	}
	if minimum > IPCVersion || current < IPCVersion {
		result := errorResult(http.StatusUpgradeRequired, "ipc_version_unsupported", "IPC version ranges do not overlap")
		return &result
	}
	return nil
}

func writeResult(writer io.Writer, result Result) {
	status := result.StatusCode
	if status == 0 {
		status = http.StatusOK
	}
	contentType := result.ContentType
	if contentType == "" {
		contentType = "application/json"
	}
	headers := fmt.Sprintf(
		"HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n",
		status,
		http.StatusText(status),
		contentType,
		len(result.Body),
	)
	_, _ = io.WriteString(writer, headers)
	_, _ = writer.Write(result.Body)
}
