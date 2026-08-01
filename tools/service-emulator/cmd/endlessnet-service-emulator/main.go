package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"sync"
	"sync/atomic"

	serviceemulator "github.com/endless-net/client-ui/tools/service-emulator"
)

func main() {
	if err := run(os.Args[1:], os.Stdout, os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, "service emulator:", err)
		os.Exit(1)
	}
}

func run(args []string, stdout, stderr io.Writer) error {
	flags := flag.NewFlagSet("endlessnet-service-emulator", flag.ContinueOnError)
	flags.SetOutput(stderr)
	pipePath := flags.String("pipe", `\\.\pipe\endlessnet-service-emulator`, "local Windows named pipe")
	scenarioPath := flags.String("scenario", "", "JSON scenario overlay")
	readyFile := flags.String("ready-file", "", "write readiness metadata to this path")
	requestsFile := flags.String("requests-file", "", "write redacted request records as JSONL")
	validateOnly := flags.Bool("validate-only", false, "validate the scenario without opening a pipe")
	maxRequests := flags.Uint64("max-requests", 0, "stop after this many requests (zero means unlimited)")
	allowDefaultPipe := flags.Bool("allow-default-pipe", false, "allow the real service's default pipe name")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return fmt.Errorf("unexpected positional arguments: %v", flags.Args())
	}
	if *pipePath == `\\.\pipe\endlessnet-service` && !*allowDefaultPipe {
		return errors.New("refusing to use the real service pipe; pass --allow-default-pipe only in an isolated test machine")
	}

	scenario, err := loadScenario(*scenarioPath)
	if err != nil {
		return err
	}
	if *validateOnly {
		fmt.Fprintf(stdout, "scenario %q is valid\n", scenario.Name)
		return nil
	}

	journal, err := newJournal(*requestsFile)
	if err != nil {
		return err
	}
	defer journal.Close()

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()
	engine, err := serviceemulator.NewEngine(scenario, journal.Record)
	if err != nil {
		return fmt.Errorf("create scenario engine: %w", err)
	}
	var requestCount atomic.Uint64
	server := &serviceemulator.Server{
		PipePath: *pipePath,
		Engine:   engine,
		Ready:    make(chan struct{}),
		RequestStarted: func() {
			if *maxRequests > 0 && requestCount.Add(1) >= *maxRequests {
				cancel()
			}
		},
	}
	errCh := make(chan error, 1)
	go func() { errCh <- server.Serve(ctx) }()

	select {
	case err := <-errCh:
		return err
	case <-server.Ready:
	}
	if err := writeReadyFile(*readyFile, *pipePath, scenario.Name); err != nil {
		cancel()
		<-errCh
		return err
	}
	fmt.Fprintf(stdout, "READY pipe=%s scenario=%q\n", *pipePath, scenario.Name)

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		return <-errCh
	}
}

func loadScenario(path string) (serviceemulator.Scenario, error) {
	if path == "" {
		scenario := serviceemulator.DefaultScenario()
		return scenario, scenario.Validate()
	}
	file, err := os.Open(path)
	if err != nil {
		return serviceemulator.Scenario{}, fmt.Errorf("open scenario: %w", err)
	}
	defer file.Close()
	scenario, err := serviceemulator.LoadScenario(file)
	if err != nil {
		return serviceemulator.Scenario{}, fmt.Errorf("load %s: %w", path, err)
	}
	return scenario, nil
}

type journal struct {
	mu      sync.Mutex
	file    *os.File
	encoder *json.Encoder
}

func newJournal(path string) (*journal, error) {
	result := &journal{}
	if path == "" {
		return result, nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, fmt.Errorf("create requests file directory: %w", err)
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return nil, fmt.Errorf("create requests file: %w", err)
	}
	result.file = file
	result.encoder = json.NewEncoder(file)
	return result, nil
}

func (j *journal) Record(interaction serviceemulator.Interaction) {
	if j.encoder == nil {
		return
	}
	j.mu.Lock()
	defer j.mu.Unlock()
	_ = j.encoder.Encode(interaction)
}

func (j *journal) Close() error {
	if j.file == nil {
		return nil
	}
	return j.file.Close()
}

func writeReadyFile(path, pipePath, scenarioName string) error {
	if path == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create ready file directory: %w", err)
	}
	payload, err := json.Marshal(map[string]any{
		"pipe":     pipePath,
		"scenario": scenarioName,
		"pid":      os.Getpid(),
	})
	if err != nil {
		return err
	}
	temporary := path + ".tmp"
	if err := os.WriteFile(temporary, payload, 0o600); err != nil {
		return fmt.Errorf("write ready file: %w", err)
	}
	if err := os.Rename(temporary, path); err != nil {
		return fmt.Errorf("publish ready file: %w", err)
	}
	return nil
}
