package packaging

import (
	"fmt"
	"strings"
	"time"
)

const (
	DefaultWindowsServicePipeName = `\\.\pipe\endlessnet-service`
	DefaultWindowsEventLogSource  = "EndlessNet Client"
	DefaultDebugLogDir            = `~\.endlessnet\logs`
)

// WindowsServiceOptions describes the installed Go service contract consumed
// by the WiX package. It is build metadata; it is not part of the Flutter app.
type WindowsServiceOptions struct {
	ServiceName        string
	DisplayName        string
	Description        string
	BinaryPath         string
	TrayPath           string
	ConfigPath         string
	WGConfigPath       string
	StatePath          string
	DiagnosticsDir     string
	IPCPipe            string
	EventLogSource     string
	Interval           time.Duration
	Timeout            time.Duration
	STUNTimeout        time.Duration
	ListenPort         int
	ReconnectMaxDelay  time.Duration
	ReconnectJitter    float64
	UserspaceWireGuard bool
	Debug              bool
	DebugLogDir        string
}

func DefaultWindowsServiceOptions() WindowsServiceOptions {
	return WindowsServiceOptions{
		ServiceName:        "endlessnet-client",
		DisplayName:        "EndlessNet Client",
		Description:        "EndlessNet client agent",
		BinaryPath:         `C:\Program Files\EndlessNet\endlessnet-client.exe`,
		TrayPath:           `C:\Program Files\EndlessNet\endlessnet-tray.exe`,
		ConfigPath:         `C:\ProgramData\EndlessNet\client.json`,
		WGConfigPath:       `C:\ProgramData\EndlessNet\endlessnet.conf`,
		StatePath:          `C:\ProgramData\EndlessNet\agent-state.json`,
		DiagnosticsDir:     `C:\ProgramData\EndlessNet\Diagnostics`,
		IPCPipe:            DefaultWindowsServicePipeName,
		EventLogSource:     DefaultWindowsEventLogSource,
		Interval:           30 * time.Second,
		Timeout:            10 * time.Second,
		STUNTimeout:        2 * time.Second,
		ReconnectMaxDelay:  5 * time.Minute,
		ReconnectJitter:    0.2,
		UserspaceWireGuard: true,
		Debug:              true,
		DebugLogDir:        DefaultDebugLogDir,
	}
}

func normalizeWindowsServiceOptions(opts WindowsServiceOptions) WindowsServiceOptions {
	defaults := DefaultWindowsServiceOptions()
	stringsWithDefaults := []struct {
		value *string
		want  string
	}{
		{&opts.ServiceName, defaults.ServiceName},
		{&opts.DisplayName, defaults.DisplayName},
		{&opts.Description, defaults.Description},
		{&opts.BinaryPath, defaults.BinaryPath},
		{&opts.TrayPath, defaults.TrayPath},
		{&opts.ConfigPath, defaults.ConfigPath},
		{&opts.WGConfigPath, defaults.WGConfigPath},
		{&opts.StatePath, defaults.StatePath},
		{&opts.DiagnosticsDir, defaults.DiagnosticsDir},
		{&opts.IPCPipe, defaults.IPCPipe},
		{&opts.EventLogSource, defaults.EventLogSource},
		{&opts.DebugLogDir, defaults.DebugLogDir},
	}
	for _, item := range stringsWithDefaults {
		if strings.TrimSpace(*item.value) == "" {
			*item.value = item.want
		}
	}
	if opts.Interval <= 0 {
		opts.Interval = defaults.Interval
	}
	if opts.Timeout <= 0 {
		opts.Timeout = defaults.Timeout
	}
	if opts.STUNTimeout <= 0 {
		opts.STUNTimeout = defaults.STUNTimeout
	}
	if opts.ReconnectMaxDelay <= 0 {
		opts.ReconnectMaxDelay = defaults.ReconnectMaxDelay
	}
	return opts
}

func windowsServiceAgentArgs(opts WindowsServiceOptions) []string {
	args := []string{
		"agent",
		"--windows-service",
		"--config", opts.ConfigPath,
		"--output", opts.WGConfigPath,
		"--state-output", opts.StatePath,
		"--diagnostics-dir", opts.DiagnosticsDir,
		"--interval", opts.Interval.String(),
		"--timeout", opts.Timeout.String(),
		"--stun-timeout", opts.STUNTimeout.String(),
		"--reconnect-max-delay", opts.ReconnectMaxDelay.String(),
		"--reconnect-jitter", fmt.Sprintf("%g", opts.ReconnectJitter),
		"--ipc-pipe", opts.IPCPipe,
		"--event-log-source", opts.EventLogSource,
	}
	if opts.Debug {
		args = append(args, "--debug", "--debug-log-dir", opts.DebugLogDir)
	}
	if opts.UserspaceWireGuard {
		args = append(args, "--userspace-wireguard")
	}
	if opts.ListenPort > 0 {
		args = append(args, "--listen-port", fmt.Sprintf("%d", opts.ListenPort))
	}
	return quoteWindowsServiceArguments(args)
}

func quoteWindowsServiceArguments(args []string) []string {
	out := make([]string, 0, len(args))
	for _, arg := range args {
		out = append(out, `"`+strings.ReplaceAll(arg, `"`, `\"`)+`"`)
	}
	return out
}

func quotePowerShellSingle(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}
