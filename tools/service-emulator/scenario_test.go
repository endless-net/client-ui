package serviceemulator

import (
	"encoding/json"
	"maps"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestContractRoutesMatchCheckedInOpenAPI(t *testing.T) {
	contractPath := filepath.Join("..", "..", "contracts", "upstream", "client-ipc-v1.openapi.yaml")
	raw, err := os.ReadFile(contractPath)
	if err != nil {
		t.Fatalf("read IPC contract: %v", err)
	}
	pathPattern := regexp.MustCompile(`(?m)^  (/[^:]+):\r?$`)
	methodPattern := regexp.MustCompile(`(?m)^    (get|post|put|patch|delete):\r?$`)
	matches := pathPattern.FindAllStringSubmatchIndex(string(raw), -1)
	want := make(map[string]string, len(matches))
	for i, match := range matches {
		blockEnd := len(raw)
		if i+1 < len(matches) {
			blockEnd = matches[i+1][0]
		}
		method := methodPattern.FindSubmatch(raw[match[1]:blockEnd])
		if method == nil {
			t.Fatalf("OpenAPI path %q has no HTTP operation", string(raw[match[2]:match[3]]))
		}
		want[string(raw[match[2]:match[3]])] = strings.ToUpper(string(method[1]))
	}
	if !maps.Equal(contractRoutes, want) {
		t.Fatalf("emulator routes = %v, OpenAPI routes = %v", contractRoutes, want)
	}
}

func TestExampleScenariosValidate(t *testing.T) {
	paths, err := filepath.Glob(filepath.Join("scenarios", "*.json"))
	if err != nil {
		t.Fatal(err)
	}
	if len(paths) == 0 {
		t.Fatal("no example scenarios found")
	}
	for _, path := range paths {
		t.Run(filepath.Base(path), func(t *testing.T) {
			file, err := os.Open(path)
			if err != nil {
				t.Fatal(err)
			}
			defer file.Close()
			if _, err := LoadScenario(file); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestDefaultEngineImplementsContractSurface(t *testing.T) {
	engine := newTestEngine(t, DefaultScenario(), nil)

	status := decodeResult(t, engine.Handle(http.MethodGet, "/status", nil))
	assertEnvelope(t, status)
	if got := status["state"]; got != "Connected" {
		t.Fatalf("initial state = %v, want Connected", got)
	}

	networks := decodeResult(t, engine.Handle(http.MethodGet, "/networks", nil))
	assertEnvelope(t, networks)
	if got := len(networks["networks"].([]any)); got != 2 {
		t.Fatalf("network count = %d, want 2", got)
	}

	selected := decodeResult(t, engine.Handle(http.MethodPost, "/network/select", []byte(`{"network_id":"net_staging"}`)))
	if got := selected["selected_network_id"]; got != "net_staging" {
		t.Fatalf("selected network = %v, want net_staging", got)
	}

	disconnected := decodeResult(t, engine.Handle(http.MethodPost, "/disconnect", []byte(`{}`)))
	if got := disconnected["state"]; got != "Disconnected" {
		t.Fatalf("disconnect state = %v, want Disconnected", got)
	}
	connected := decodeResult(t, engine.Handle(http.MethodPost, "/connect", []byte(`{}`)))
	if got := connected["state"]; got != "Connected" {
		t.Fatalf("connect state = %v, want Connected", got)
	}

	identity := decodeResult(t, engine.Handle(http.MethodGet, "/server-identity", nil))
	assertEnvelope(t, identity)
	keyID := identity["announced_key_id"].(string)
	trusted := decodeResult(t, engine.Handle(http.MethodPost, "/server-identity/trust", []byte(`{"confirmed":true,"confirmed_key_id":"`+keyID+`"}`)))
	if got := trusted["state"]; got != "Connected" {
		t.Fatalf("trusted state = %v, want Connected", got)
	}

	diagnostics := decodeResult(t, engine.Handle(http.MethodGet, "/diagnostics", nil))
	assertEnvelope(t, diagnostics)
	diagnosticsPayload, ok := diagnostics["diagnostics"].(map[string]any)
	if !ok || diagnosticsPayload["status"] == nil || diagnosticsPayload["recent_logs"] == nil {
		t.Fatal("diagnostics response omitted diagnostics.status or diagnostics.recent_logs")
	}
	diagnosticsStatus := diagnosticsPayload["status"].(map[string]any)
	diagnosticsAgent := diagnosticsStatus["agent"].(map[string]any)
	if len(diagnosticsAgent["peers"].([]any)) != 1 {
		t.Fatalf("diagnostics response omitted peer path data: %#v", diagnosticsAgent)
	}
	bundle := decodeResult(t, engine.Handle(http.MethodPost, "/diagnostics/bundle", []byte(`{"log_limit":100}`)))
	assertEnvelope(t, bundle)
	if bundle["path"] == nil || bundle["size_bytes"] == nil {
		t.Fatal("diagnostics bundle response omitted path or size_bytes")
	}
	logs := decodeResult(t, engine.Handle(http.MethodGet, "/logs/recent?limit=1", nil))
	assertEnvelope(t, logs)

	loggedOut := decodeResult(t, engine.Handle(http.MethodPost, "/logout", []byte(`{}`)))
	if got := loggedOut["state"]; got != "NeedsEnrollment" {
		t.Fatalf("logout state = %v, want NeedsEnrollment", got)
	}
	enrolled := decodeResult(t, engine.Handle(http.MethodPost, "/enroll", []byte(`{"enroll_token":"enr_secret","mode":"workstation"}`)))
	if got := enrolled["state"]; got != "Connected" {
		t.Fatalf("enrolled state = %v, want Connected", got)
	}

	events := engine.Handle(http.MethodGet, "/events", nil)
	if events.ContentType != "application/x-ndjson" {
		t.Fatalf("events content type = %q", events.ContentType)
	}
	lines := strings.Split(strings.TrimSpace(string(events.Body)), "\n")
	if len(lines) != 2 {
		t.Fatalf("event lines = %d, want 2", len(lines))
	}
	for _, line := range lines {
		var event map[string]any
		if err := json.Unmarshal([]byte(line), &event); err != nil {
			t.Fatalf("decode event: %v", err)
		}
		assertEnvelope(t, event)
	}
}

func TestScriptedRouteChecksBodyPatchesStatusAndRepeats(t *testing.T) {
	scenarioJSON := `{
  "schema_version": 1,
  "name": "scripted-error",
  "routes": [{
    "method": "POST",
    "path": "/connect",
    "repeat_last": true,
    "responses": [{
      "expect_body": {},
      "status": 503,
		"body": {"error_code": "connect_failed", "error": "offline"},
      "delay_ms": 25,
      "status_patch": {"state": "Degraded", "control_state": "offline_cache"}
    }]
  }]
}`
	scenario, err := LoadScenario(strings.NewReader(scenarioJSON))
	if err != nil {
		t.Fatal(err)
	}
	engine := newTestEngine(t, scenario, nil)

	result := engine.Handle(http.MethodPost, "/connect", []byte(`{}`))
	if result.StatusCode != 503 || result.Delay.Milliseconds() != 25 {
		t.Fatalf("scripted result = status %d delay %s", result.StatusCode, result.Delay)
	}
	payload := decodeResult(t, result)
	assertEnvelope(t, payload)
	if payload["error_code"] != "connect_failed" {
		t.Fatalf("error code = %v", payload["error_code"])
	}

	repeated := engine.Handle(http.MethodPost, "/connect", []byte(`{}`))
	if repeated.StatusCode != 503 {
		t.Fatalf("repeated status = %d, want 503", repeated.StatusCode)
	}
	status := decodeResult(t, engine.Handle(http.MethodGet, "/status", nil))
	if status["state"] != "Degraded" || status["control_state"] != "offline_cache" {
		t.Fatalf("patched status = %#v", status)
	}
}

func TestScriptedRouteRejectsUnexpectedBodyAndExhaustion(t *testing.T) {
	scenarioJSON := `{
  "schema_version": 1,
  "name": "strict-sequence",
  "routes": [{
    "method": "POST",
    "path": "/network/select",
    "responses": [{
      "expect_body": {"network_id": "net_primary"},
		"body": {"state": "Connected", "desired_state": "connected", "selected_network_id": "net_primary", "selected_network": {"id": "net_primary"}, "node_id": "node_emulator", "map_revision": 1}
    }]
  }]
}`
	scenario, err := LoadScenario(strings.NewReader(scenarioJSON))
	if err != nil {
		t.Fatal(err)
	}
	engine := newTestEngine(t, scenario, nil)

	mismatch := decodeResult(t, engine.Handle(http.MethodPost, "/network/select", []byte(`{"network_id":"wrong"}`)))
	if mismatch["error_code"] != "request_failed" {
		t.Fatalf("mismatch error = %#v", mismatch)
	}
	exhausted := decodeResult(t, engine.Handle(http.MethodPost, "/network/select", []byte(`{"network_id":"net_primary"}`)))
	if exhausted["error_code"] != "request_failed" {
		t.Fatalf("exhausted error = %#v", exhausted)
	}
}

func TestInteractionRedactsEnrollmentSecrets(t *testing.T) {
	var got Interaction
	engine := newTestEngine(t, DefaultScenario(), func(interaction Interaction) {
		got = interaction
	})
	engine.Handle(http.MethodPost, "/enroll", []byte(`{"enroll_token":"enr_secret","mode":"workstation"}`))

	if got.RequestBody["enroll_token"] != "<redacted>" {
		t.Fatalf("journal leaked enrollment token: %#v", got.RequestBody)
	}
	if got.Method != http.MethodPost || got.Target != "/enroll" || got.Sequence != 1 {
		t.Fatalf("unexpected interaction: %#v", got)
	}
}

func TestInvalidMethodAndPathUseContractErrors(t *testing.T) {
	engine := newTestEngine(t, DefaultScenario(), nil)
	method := decodeResult(t, engine.Handle(http.MethodPost, "/status", []byte(`{}`)))
	if method["error_code"] != "method_not_allowed" {
		t.Fatalf("method error = %#v", method)
	}
	missing := decodeResult(t, engine.Handle(http.MethodGet, "/missing", nil))
	if missing["error_code"] != "not_found" {
		t.Fatalf("missing error = %#v", missing)
	}
}

func TestScenarioRequiresVersionAndContractRoute(t *testing.T) {
	if _, err := LoadScenario(strings.NewReader(`{"name":"missing-version"}`)); err == nil || !strings.Contains(err.Error(), "schema_version is required") {
		t.Fatalf("missing schema version error = %v", err)
	}
	_, err := LoadScenario(strings.NewReader(`{
  "schema_version": 1,
  "name": "route-typo",
  "routes": [{"method":"GET","path":"/stats","responses":[{}]}]
}`))
	if err == nil || !strings.Contains(err.Error(), "not in the IPC contract") {
		t.Fatalf("route typo error = %v", err)
	}
}

func newTestEngine(t *testing.T, scenario Scenario, observer Observer) *Engine {
	t.Helper()
	engine, err := NewEngine(scenario, observer)
	if err != nil {
		t.Fatal(err)
	}
	return engine
}

func decodeResult(t *testing.T, result Result) map[string]any {
	t.Helper()
	var payload map[string]any
	if err := json.Unmarshal(result.Body, &payload); err != nil {
		t.Fatalf("decode response %q: %v", result.Body, err)
	}
	return payload
}

func assertEnvelope(t *testing.T, payload map[string]any) {
	t.Helper()
	if payload["ipc_protocol"] != IPCProtocol || payload["ipc_version"] != float64(IPCVersion) || payload["ipc_min_supported_version"] != float64(IPCVersion) || payload["ipc_negotiated_version"] != float64(IPCVersion) {
		t.Fatalf("invalid IPC envelope: %#v", payload)
	}
}
