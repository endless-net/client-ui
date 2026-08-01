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

	coreDefaultAgentInterval          = 30 * time.Second
	coreDefaultAgentTimeout           = 5 * time.Second
	coreDefaultAgentSTUNTimeout       = 2 * time.Second
	coreDefaultAgentReconnectMaxDelay = 5 * time.Minute
	coreDefaultAgentReconnectJitter   = 0.2
)

// WindowsServiceOptions describes the installed Go service contract consumed
// by the WiX package. It is build metadata; it is not part of the Flutter app.
type WindowsServiceOptions struct {
	ServiceName       string
	DisplayName       string
	Description       string
	BinaryPath        string
	ConfigPath        string
	StatePath         string
	DiagnosticsDir    string
	IPCPipe           string
	EventLogSource    string
	Interval          time.Duration
	Timeout           time.Duration
	STUNTimeout       time.Duration
	ListenPort        int
	ReconnectMaxDelay time.Duration
	ReconnectJitter   float64
	Debug             bool
	DebugLogDir       string
}

func DefaultWindowsServiceOptions() WindowsServiceOptions {
	return WindowsServiceOptions{
		ServiceName:       "endlessnet-client",
		DisplayName:       "EndlessNet Client",
		Description:       "EndlessNet client agent",
		BinaryPath:        `C:\Program Files\EndlessNet\endlessnet-client.exe`,
		ConfigPath:        `C:\ProgramData\EndlessNet\client.json`,
		StatePath:         `C:\ProgramData\EndlessNet\agent-state.json`,
		DiagnosticsDir:    `C:\ProgramData\EndlessNet\Diagnostics`,
		IPCPipe:           DefaultWindowsServicePipeName,
		EventLogSource:    DefaultWindowsEventLogSource,
		Interval:          coreDefaultAgentInterval,
		Timeout:           10 * time.Second,
		STUNTimeout:       coreDefaultAgentSTUNTimeout,
		ReconnectMaxDelay: coreDefaultAgentReconnectMaxDelay,
		ReconnectJitter:   coreDefaultAgentReconnectJitter,
		Debug:             true,
		DebugLogDir:       DefaultDebugLogDir,
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
		{&opts.ConfigPath, defaults.ConfigPath},
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
		"--state-output", opts.StatePath,
		"--diagnostics-dir", opts.DiagnosticsDir,
	}
	if opts.Interval != coreDefaultAgentInterval {
		args = append(args, "--interval", opts.Interval.String())
	}
	if opts.Timeout != coreDefaultAgentTimeout {
		args = append(args, "--timeout", opts.Timeout.String())
	}
	if opts.STUNTimeout != coreDefaultAgentSTUNTimeout {
		args = append(args, "--stun-timeout", opts.STUNTimeout.String())
	}
	if opts.ReconnectMaxDelay != coreDefaultAgentReconnectMaxDelay {
		args = append(args, "--reconnect-max-delay", opts.ReconnectMaxDelay.String())
	}
	if opts.ReconnectJitter != coreDefaultAgentReconnectJitter {
		args = append(args, "--reconnect-jitter", fmt.Sprintf("%g", opts.ReconnectJitter))
	}
	if opts.IPCPipe != DefaultWindowsServicePipeName {
		args = append(args, "--ipc-pipe", opts.IPCPipe)
	}
	if opts.EventLogSource != DefaultWindowsEventLogSource {
		args = append(args, "--event-log-source", opts.EventLogSource)
	}
	if opts.Debug {
		args = append(args, "--debug")
		if opts.DebugLogDir != DefaultDebugLogDir {
			args = append(args, "--debug-log-dir", opts.DebugLogDir)
		}
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
