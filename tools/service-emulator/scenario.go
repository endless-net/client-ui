package serviceemulator

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	SchemaVersion       = 1
	IPCProtocol         = "endlessnet-client-ipc"
	IPCVersion          = 1
	IPCProtocolHeader   = "X-EndlessNet-IPC-Protocol"
	IPCVersionHeader    = "X-EndlessNet-IPC-Version"
	IPCMinVersionHeader = "X-EndlessNet-IPC-Min-Supported-Version"
	DefaultMaxBodyBytes = 1 << 20
)

var contractRoutes = map[string]string{
	"/status":                http.MethodGet,
	"/events":                http.MethodGet,
	"/enroll":                http.MethodPost,
	"/connect":               http.MethodPost,
	"/server-identity":       http.MethodGet,
	"/server-identity/trust": http.MethodPost,
	"/disconnect":            http.MethodPost,
	"/logout":                http.MethodPost,
	"/networks":              http.MethodGet,
	"/network/select":        http.MethodPost,
	"/diagnostics":           http.MethodGet,
	"/diagnostics/bundle":    http.MethodPost,
	"/logs/recent":           http.MethodGet,
}

// Scenario is a deterministic, contract-shaped service model. Scenario files
// are overlays on DefaultScenario, so tests only need to describe the state and
// responses that matter to them.
type Scenario struct {
	SchemaVersion  int              `json:"schema_version"`
	Name           string           `json:"name"`
	InitialStatus  map[string]any   `json:"initial_status"`
	Networks       []map[string]any `json:"networks"`
	ServerIdentity map[string]any   `json:"server_identity"`
	Logs           []map[string]any `json:"logs"`
	Routes         []ScriptedRoute  `json:"routes"`
}

type ScriptedRoute struct {
	Method     string             `json:"method"`
	Path       string             `json:"path"`
	RepeatLast bool               `json:"repeat_last,omitempty"`
	Responses  []ScriptedResponse `json:"responses"`
}

type ScriptedResponse struct {
	ExpectBody      *json.RawMessage `json:"expect_body,omitempty"`
	Status          int              `json:"status,omitempty"`
	Body            map[string]any   `json:"body,omitempty"`
	RawBody         *string          `json:"raw_body,omitempty"`
	ContentType     string           `json:"content_type,omitempty"`
	DelayMS         int              `json:"delay_ms,omitempty"`
	CloseConnection bool             `json:"close_connection,omitempty"`
	StatusPatch     map[string]any   `json:"status_patch,omitempty"`
}

type Result struct {
	StatusCode      int
	ContentType     string
	Body            []byte
	Delay           time.Duration
	CloseConnection bool
}

type Interaction struct {
	Sequence       uint64         `json:"sequence"`
	Timestamp      string         `json:"timestamp"`
	Method         string         `json:"method"`
	Target         string         `json:"target"`
	RequestBody    map[string]any `json:"request_body,omitempty"`
	ResponseStatus int            `json:"response_status,omitempty"`
	Scripted       bool           `json:"scripted"`
	Failure        string         `json:"failure,omitempty"`
}

type Observer func(Interaction)

type Engine struct {
	mu          sync.Mutex
	scenario    Scenario
	status      map[string]any
	routeCursor map[string]int
	sequence    uint64
	observer    Observer
}

func DefaultScenario() Scenario {
	return Scenario{
		SchemaVersion: SchemaVersion,
		Name:          "connected-happy-path",
		InitialStatus: map[string]any{
			"ipc_protocol":              IPCProtocol,
			"ipc_version":               IPCVersion,
			"ipc_min_supported_version": IPCVersion,
			"ipc_negotiated_version":    IPCVersion,
			"service_version":           "service-emulator",
			"service_commit":            "test-fixture",
			"service_build_date":        "2026-01-01T00:00:00Z",
			"state":                     "Connected",
			"control_state":             "ready",
			"desired_state":             "connected",
			"user_disconnected":         false,
			"connection_intent": map[string]any{
				"desired_state": "connected",
				"reason":        "user_connect",
				"updated_at":    "2026-01-01T00:00:00Z",
			},
			"control_plane_urls":           []any{"https://api.example.test"},
			"account_id":                   "acc_emulator",
			"node_id":                      "node_emulator",
			"hostname":                     "windows-emulator",
			"network_id":                   "net_primary",
			"network_name":                 "primary",
			"overlay_ip":                   "100.64.0.10",
			"map_revision":                 1,
			"peer_count":                   1,
			"cached_map_present":           true,
			"cached_map_valid":             true,
			"map_signing_trust_present":    true,
			"token_present":                true,
			"node_credential_present":      true,
			"device_fingerprint_present":   true,
			"identity_private_key_present": true,
			"private_key_present":          true,
			"agent": map[string]any{
				"state_present":        true,
				"snapshot_state":       "current",
				"generated_at":         "2026-01-01T00:00:00Z",
				"node_id":              "node_emulator",
				"network_id":           "net_primary",
				"overlay_ip":           "100.64.0.10",
				"stun_ok":              true,
				"relay_ok":             true,
				"selected_path_counts": map[string]any{"direct": 1},
				"peers": []any{
					map[string]any{
						"peer_id":           "node_peer_a",
						"hostname":          "peer-a",
						"selected_path":     "direct",
						"selected_endpoint": "192.168.1.20:51820",
						"selection_reason":  "authenticated direct path selected after successful candidate probe",
						"direct": map[string]any{
							"type": "direct", "tier": "lan_direct", "state": "reachable",
							"endpoint": "192.168.1.20:51820", "rtt_ms": 4.2,
						},
						"candidates": []any{
							map[string]any{
								"type": "direct", "tier": "lan_direct", "state": "reachable",
								"endpoint": "192.168.1.20:51820", "rtt_ms": 4.2,
							},
						},
						"relay": map[string]any{
							"type": "relay", "tier": "relay", "state": "reachable",
							"endpoint": "relay.example.test:443", "protocol": "tcp",
						},
					},
				},
			},
		},
		Networks: []map[string]any{
			{
				"id":         "net_primary",
				"name":       "primary",
				"cidr":       "100.64.0.0/24",
				"account_id": "acc_emulator",
			},
			{
				"id":         "net_staging",
				"name":       "staging",
				"cidr":       "100.65.0.0/24",
				"account_id": "acc_emulator",
			},
		},
		ServerIdentity: map[string]any{
			"control_plane_url": "https://api.example.test",
			"trusted_key_id":    "ed25519:emulator",
			"announced_key_id":  "ed25519:emulator",
			"changed":           false,
		},
		Logs: []map[string]any{
			{
				"timestamp": "2026-01-01T00:00:00Z",
				"message":   "service emulator ready",
			},
		},
	}
}

// LoadScenario decodes a strict JSON scenario and overlays it on the built-in
// contract fixture. Strict decoding catches misspelled fault-injection fields.
func LoadScenario(r io.Reader) (Scenario, error) {
	var overlay Scenario
	decoder := json.NewDecoder(r)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&overlay); err != nil {
		return Scenario{}, fmt.Errorf("decode scenario: %w", err)
	}
	if err := ensureJSONEOF(decoder); err != nil {
		return Scenario{}, err
	}
	if overlay.SchemaVersion == 0 {
		return Scenario{}, errors.New("scenario schema_version is required")
	}

	scenario := DefaultScenario()
	scenario.SchemaVersion = overlay.SchemaVersion
	if overlay.Name != "" {
		scenario.Name = overlay.Name
	}
	mergeMap(scenario.InitialStatus, overlay.InitialStatus)
	if overlay.Networks != nil {
		scenario.Networks = overlay.Networks
	}
	mergeMap(scenario.ServerIdentity, overlay.ServerIdentity)
	if overlay.Logs != nil {
		scenario.Logs = overlay.Logs
	}
	if overlay.Routes != nil {
		scenario.Routes = overlay.Routes
	}
	if err := scenario.Validate(); err != nil {
		return Scenario{}, err
	}
	return scenario, nil
}

func ensureJSONEOF(decoder *json.Decoder) error {
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("scenario contains more than one JSON value")
		}
		return fmt.Errorf("decode trailing scenario data: %w", err)
	}
	return nil
}

func (s Scenario) Validate() error {
	if s.SchemaVersion != SchemaVersion {
		return fmt.Errorf("scenario schema_version must be %d", SchemaVersion)
	}
	if strings.TrimSpace(s.Name) == "" {
		return errors.New("scenario name is required")
	}
	for key, want := range map[string]any{
		"ipc_protocol":              IPCProtocol,
		"ipc_version":               float64(IPCVersion),
		"ipc_min_supported_version": float64(IPCVersion),
	} {
		got, ok := s.InitialStatus[key]
		if !ok || fmt.Sprint(got) != fmt.Sprint(want) {
			return fmt.Errorf("initial_status.%s must be %v", key, want)
		}
	}
	for _, key := range []string{
		"state", "control_state", "desired_state", "cached_map_present",
		"cached_map_valid", "map_signing_trust_present", "token_present",
		"node_credential_present", "device_fingerprint_present",
		"identity_private_key_present", "private_key_present",
	} {
		if _, ok := s.InitialStatus[key]; !ok {
			return fmt.Errorf("initial_status.%s is required by the IPC contract", key)
		}
	}

	seen := make(map[string]struct{}, len(s.Routes))
	for i := range s.Routes {
		route := &s.Routes[i]
		route.Method = strings.ToUpper(strings.TrimSpace(route.Method))
		route.Path = strings.TrimSpace(route.Path)
		if route.Method == "" || route.Path == "" || !strings.HasPrefix(route.Path, "/") {
			return fmt.Errorf("routes[%d] requires an HTTP method and absolute path", i)
		}
		if len(route.Responses) == 0 {
			return fmt.Errorf("routes[%d].responses must not be empty", i)
		}
		key := routeKey(route.Method, route.Path)
		wantMethod, known := contractRoutes[route.Path]
		if !known {
			return fmt.Errorf("routes[%d].path is not in the IPC contract: %s", i, route.Path)
		}
		if route.Method != wantMethod {
			return fmt.Errorf("routes[%d].method for %s must be %s", i, route.Path, wantMethod)
		}
		if _, ok := seen[key]; ok {
			return fmt.Errorf("duplicate scripted route %s", key)
		}
		seen[key] = struct{}{}
		for j, response := range route.Responses {
			if response.Status != 0 && (response.Status < 100 || response.Status > 599) {
				return fmt.Errorf("routes[%d].responses[%d].status is invalid", i, j)
			}
			if response.DelayMS < 0 {
				return fmt.Errorf("routes[%d].responses[%d].delay_ms must not be negative", i, j)
			}
			if response.RawBody != nil && response.Body != nil {
				return fmt.Errorf("routes[%d].responses[%d] cannot set body and raw_body", i, j)
			}
			if strings.ContainsAny(response.ContentType, "\r\n") {
				return fmt.Errorf("routes[%d].responses[%d].content_type contains a newline", i, j)
			}
			if response.ExpectBody != nil {
				var body any
				if err := json.Unmarshal(*response.ExpectBody, &body); err != nil {
					return fmt.Errorf("routes[%d].responses[%d].expect_body: %w", i, j, err)
				}
				if _, ok := body.(map[string]any); !ok {
					return fmt.Errorf("routes[%d].responses[%d].expect_body must be a JSON object", i, j)
				}
			}
		}
	}
	return nil
}

func NewEngine(scenario Scenario, observer Observer) (*Engine, error) {
	if err := scenario.Validate(); err != nil {
		return nil, err
	}
	cloned, err := cloneScenario(scenario)
	if err != nil {
		return nil, err
	}
	return &Engine{
		scenario:    cloned,
		status:      cloneMap(cloned.InitialStatus),
		routeCursor: make(map[string]int),
		observer:    observer,
	}, nil
}

func cloneScenario(s Scenario) (Scenario, error) {
	raw, err := json.Marshal(s)
	if err != nil {
		return Scenario{}, fmt.Errorf("clone scenario: %w", err)
	}
	var cloned Scenario
	if err := json.Unmarshal(raw, &cloned); err != nil {
		return Scenario{}, fmt.Errorf("clone scenario: %w", err)
	}
	return cloned, nil
}

// Handle evaluates one complete local HTTP request. It is safe for concurrent
// named-pipe connections; scripted response queues are consumed atomically.
func (e *Engine) Handle(method, target string, rawBody []byte) Result {
	e.mu.Lock()
	defer e.mu.Unlock()

	method = strings.ToUpper(strings.TrimSpace(method))
	parsed, err := url.ParseRequestURI(target)
	if err != nil {
		return e.finish(method, target, nil, false, errorResult(http.StatusBadRequest, "invalid_json", "invalid request target"), err.Error())
	}
	requestBody, bodyErr := decodeRequestBody(rawBody)
	if bodyErr != nil {
		return e.finish(method, target, nil, false, errorResult(http.StatusBadRequest, "invalid_json", bodyErr.Error()), bodyErr.Error())
	}

	if result, ok := e.scripted(method, parsed.Path, rawBody); ok {
		failure := ""
		if result.StatusCode >= 400 {
			failure = http.StatusText(result.StatusCode)
		}
		return e.finish(method, target, requestBody, true, result, failure)
	}

	result := e.builtin(method, parsed, requestBody)
	failure := ""
	if result.StatusCode >= 400 {
		failure = http.StatusText(result.StatusCode)
	}
	return e.finish(method, target, requestBody, false, result, failure)
}

func (e *Engine) scripted(method, path string, rawBody []byte) (Result, bool) {
	key := routeKey(method, path)
	for _, route := range e.scenario.Routes {
		if routeKey(route.Method, route.Path) != key {
			continue
		}
		cursor := e.routeCursor[key]
		if cursor >= len(route.Responses) {
			if !route.RepeatLast {
				return errorResult(http.StatusInternalServerError, "request_failed", "scripted response queue exhausted for "+key), true
			}
			cursor = len(route.Responses) - 1
		} else {
			e.routeCursor[key] = cursor + 1
		}
		response := route.Responses[cursor]
		if response.ExpectBody != nil && !sameJSONObject(rawBody, *response.ExpectBody) {
			return errorResult(http.StatusBadRequest, "request_failed", "request body did not match scenario expectation for "+key), true
		}
		mergeMap(e.status, response.StatusPatch)
		return scriptedResult(response), true
	}
	return Result{}, false
}

func scriptedResult(response ScriptedResponse) Result {
	status := response.Status
	if status == 0 {
		status = http.StatusOK
	}
	contentType := response.ContentType
	if contentType == "" {
		contentType = "application/json"
	}
	var body []byte
	if response.RawBody != nil {
		body = []byte(*response.RawBody)
	} else {
		payload := cloneMap(response.Body)
		if payload == nil {
			payload = map[string]any{}
		}
		addEnvelope(payload)
		body, _ = json.Marshal(payload)
	}
	return Result{
		StatusCode:      status,
		ContentType:     contentType,
		Body:            body,
		Delay:           time.Duration(response.DelayMS) * time.Millisecond,
		CloseConnection: response.CloseConnection,
	}
}

func (e *Engine) builtin(method string, requestURL *url.URL, body map[string]any) Result {
	wantMethod, known := contractRoutes[requestURL.Path]
	if !known {
		return errorResult(http.StatusNotFound, "not_found", "unknown IPC path")
	}
	if method != wantMethod {
		return errorResult(http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	}

	switch requestURL.Path {
	case "/status":
		return jsonResult(http.StatusOK, e.status)
	case "/events":
		return e.eventsResult()
	case "/connect":
		if err := requireEmptyObject(body); err != nil {
			return errorResult(http.StatusBadRequest, "invalid_json", err.Error())
		}
		e.setConnectionState("Connected", "ready", "connected", false)
		return jsonResult(http.StatusOK, e.connectResponse())
	case "/disconnect":
		if err := requireEmptyObject(body); err != nil {
			return errorResult(http.StatusBadRequest, "invalid_json", err.Error())
		}
		e.setConnectionState("Disconnected", "disconnected", "disconnected", true)
		return jsonResult(http.StatusOK, map[string]any{
			"state":             e.status["state"],
			"desired_state":     e.status["desired_state"],
			"user_disconnected": e.status["user_disconnected"],
			"wireguard":         wireGuardApplyResult(true),
		})
	case "/logout":
		if err := requireEmptyObject(body); err != nil {
			return errorResult(http.StatusBadRequest, "invalid_json", err.Error())
		}
		e.logout()
		return jsonResult(http.StatusOK, map[string]any{"state": e.status["state"]})
	case "/enroll":
		return e.enroll(body)
	case "/server-identity":
		return jsonResult(http.StatusOK, e.scenario.ServerIdentity)
	case "/server-identity/trust":
		return e.trustServer(body)
	case "/networks":
		return jsonResult(http.StatusOK, map[string]any{
			"networks":            e.scenario.Networks,
			"selected_network_id": stringValue(e.status["network_id"]),
		})
	case "/network/select":
		return e.selectNetwork(body)
	case "/diagnostics":
		return e.diagnosticsResult()
	case "/diagnostics/bundle":
		return e.diagnosticsBundleResult(body)
	case "/logs/recent":
		return e.logsResult(requestURL.Query())
	default:
		panic("unreachable contract route")
	}
}

func (e *Engine) enroll(body map[string]any) Result {
	if err := requireOnlyKeys(body, "enroll_token", "server", "mode", "hostname", "idempotency_key"); err != nil {
		return errorResult(http.StatusBadRequest, "invalid_json", err.Error())
	}
	allowedModes := []string{"workstation", "server", "subnet-router", "interactive"}
	mode := stringValue(body["mode"])
	if mode != "" && !slices.Contains(allowedModes, mode) {
		return errorResult(http.StatusBadRequest, "invalid_json", "unsupported enrollment mode")
	}
	e.setConnectionState("Connected", "ready", "connected", false)
	mergeMap(e.status, map[string]any{
		"account_id":                   "acc_emulator",
		"node_id":                      "node_emulator",
		"hostname":                     firstNonEmpty(stringValue(body["hostname"]), "windows-emulator"),
		"network_id":                   "net_primary",
		"network_name":                 "primary",
		"overlay_ip":                   "100.64.0.10",
		"cached_map_present":           true,
		"cached_map_valid":             true,
		"map_signing_trust_present":    true,
		"token_present":                true,
		"node_credential_present":      true,
		"device_fingerprint_present":   true,
		"identity_private_key_present": true,
		"private_key_present":          true,
	})
	return jsonResult(http.StatusOK, e.status)
}

func (e *Engine) trustServer(body map[string]any) Result {
	if err := requireOnlyKeys(body, "confirmed", "confirmed_key_id"); err != nil {
		return errorResult(http.StatusBadRequest, "invalid_json", err.Error())
	}
	confirmed, _ := body["confirmed"].(bool)
	keyID := stringValue(body["confirmed_key_id"])
	announced := stringValue(e.scenario.ServerIdentity["announced_key_id"])
	if !confirmed || keyID == "" || keyID != announced {
		return errorResult(http.StatusBadRequest, "request_failed", "confirmed_key_id must match the announced server identity")
	}
	e.scenario.ServerIdentity["trusted_key_id"] = keyID
	e.scenario.ServerIdentity["changed"] = false
	e.setConnectionState("Connected", "ready", "connected", false)
	result := e.connectResponse()
	result["server_identity_updated"] = true
	result["trusted_key_id"] = keyID
	return jsonResult(http.StatusOK, result)
}

func (e *Engine) selectNetwork(body map[string]any) Result {
	if err := requireOnlyKeys(body, "network_id", "network_name"); err != nil {
		return errorResult(http.StatusBadRequest, "invalid_json", err.Error())
	}
	id := stringValue(body["network_id"])
	name := stringValue(body["network_name"])
	if id == "" && name == "" {
		return errorResult(http.StatusBadRequest, "network_ref_required", "network_id or network_name is required")
	}
	for _, network := range e.scenario.Networks {
		if (id != "" && stringValue(network["id"]) == id) || (name != "" && stringValue(network["name"]) == name) {
			e.status["network_id"] = network["id"]
			e.status["network_name"] = network["name"]
			result := map[string]any{
				"state":               e.status["state"],
				"desired_state":       e.status["desired_state"],
				"selected_network_id": network["id"],
				"selected_network":    network,
				"node_id":             e.status["node_id"],
				"map_revision":        e.status["map_revision"],
			}
			return jsonResult(http.StatusOK, result)
		}
	}
	return errorResult(http.StatusNotFound, "not_found", "network was not found")
}

func (e *Engine) diagnosticsResult() Result {
	return jsonResult(http.StatusOK, map[string]any{
		"diagnostics": map[string]any{
			"generated_at": time.Now().UTC().Format(time.RFC3339Nano),
			"client": map[string]any{
				"product": "endlessnet-client", "version": "service-emulator",
				"commit": "test-fixture", "build_date": "2026-01-01T00:00:00Z",
				"target_os": "windows", "target_arch": "amd64",
			},
			"runtime": map[string]any{
				"goos": "windows", "goarch": "amd64", "go_version": "emulated",
				"os": map[string]any{"name": "Windows"},
			},
			"status":      e.status,
			"last_errors": []any{},
			"config": map[string]any{
				"control_plane_urls":           e.status["control_plane_urls"],
				"node_id":                      e.status["node_id"],
				"map_revision":                 e.status["map_revision"],
				"map_signing_trust_present":    e.status["map_signing_trust_present"],
				"token_present":                e.status["token_present"],
				"identity_private_key_present": e.status["identity_private_key_present"],
				"private_key_present":          e.status["private_key_present"],
				"node_credential_present":      e.status["node_credential_present"],
				"device_fingerprint_present":   e.status["device_fingerprint_present"],
				"cached_map_present":           e.status["cached_map_present"],
			},
			"recent_logs":          e.scenario.Logs,
			"interfaces":           []any{},
			"route_conflict_count": 0,
			"route_conflicts":      []any{},
		},
	})
}

func (e *Engine) diagnosticsBundleResult(body map[string]any) Result {
	if err := requireOnlyKeys(body, "log_limit"); err != nil {
		return errorResult(http.StatusBadRequest, "invalid_json", err.Error())
	}
	if raw, ok := body["log_limit"]; ok {
		limit, err := strconv.Atoi(stringValue(raw))
		if err != nil || limit < 1 || limit > 1000 {
			return errorResult(http.StatusBadRequest, "invalid_json", "log_limit must be between 1 and 1000")
		}
	}
	return jsonResult(http.StatusOK, map[string]any{
		"path":       `C:\Temp\endlessnet-emulator-diagnostics.zip`,
		"created_at": "2026-01-01T00:00:00Z",
		"expires_at": "2026-01-01T01:00:00Z",
		"size_bytes": 1024,
		"reused":     false,
	})
}

func (e *Engine) logsResult(query url.Values) Result {
	limit := len(e.scenario.Logs)
	if raw := query.Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 1000 {
			return errorResult(http.StatusBadRequest, "invalid_json", "limit must be between 1 and 1000")
		}
		limit = min(limit, parsed)
	}
	logs := e.scenario.Logs[len(e.scenario.Logs)-limit:]
	return jsonResult(http.StatusOK, map[string]any{"logs": logs})
}

func (e *Engine) eventsResult() Result {
	hello := envelope(map[string]any{
		"event_type":   "hello",
		"sequence":     1,
		"generated_at": time.Now().UTC().Format(time.RFC3339Nano),
	})
	statusChanged := envelope(map[string]any{
		"event_type":   "status_changed",
		"sequence":     2,
		"generated_at": time.Now().UTC().Format(time.RFC3339Nano),
		"status":       cloneMap(e.status),
	})
	first, _ := json.Marshal(hello)
	second, _ := json.Marshal(statusChanged)
	return Result{
		StatusCode:  http.StatusOK,
		ContentType: "application/x-ndjson",
		Body:        bytes.Join([][]byte{first, second, nil}, []byte("\n")),
	}
}

func (e *Engine) setConnectionState(state, controlState, desiredState string, disconnected bool) {
	mergeMap(e.status, map[string]any{
		"state":             state,
		"control_state":     controlState,
		"desired_state":     desiredState,
		"user_disconnected": disconnected,
		"connection_intent": map[string]any{
			"desired_state": desiredState,
			"reason":        map[bool]string{true: "user_disconnect", false: "user_connect"}[disconnected],
			"updated_at":    time.Now().UTC().Format(time.RFC3339Nano),
		},
	})
}

func (e *Engine) logout() {
	e.setConnectionState("NeedsEnrollment", "not_registered", "disconnected", false)
	for _, key := range []string{
		"account_id", "node_id", "network_id", "network_name", "overlay_ip",
		"overlay_ipv6", "agent", "control",
	} {
		delete(e.status, key)
	}
	mergeMap(e.status, map[string]any{
		"map_signing_trust_present":    false,
		"token_present":                false,
		"cached_map_present":           false,
		"cached_map_valid":             false,
		"node_credential_present":      false,
		"device_fingerprint_present":   false,
		"identity_private_key_present": false,
		"private_key_present":          false,
		"peer_count":                   0,
	})
}

func (e *Engine) connectResponse() map[string]any {
	result := map[string]any{
		"state":             e.status["state"],
		"control_state":     e.status["control_state"],
		"desired_state":     e.status["desired_state"],
		"user_disconnected": e.status["user_disconnected"],
		"wireguard":         wireGuardApplyResult(true),
	}
	for _, key := range []string{"node_id", "network_id", "map_revision"} {
		if value, present := e.status[key]; present {
			result[key] = value
		}
	}
	return result
}

func wireGuardApplyResult(changed bool) map[string]any {
	return map[string]any{
		"ok":      true,
		"method":  "wireguard-go",
		"changed": changed,
	}
}

func (e *Engine) finish(method, target string, requestBody map[string]any, scripted bool, result Result, failure string) Result {
	e.sequence++
	if e.observer != nil {
		e.observer(Interaction{
			Sequence:       e.sequence,
			Timestamp:      time.Now().UTC().Format(time.RFC3339Nano),
			Method:         method,
			Target:         target,
			RequestBody:    redactRequest(requestBody),
			ResponseStatus: result.StatusCode,
			Scripted:       scripted,
			Failure:        failure,
		})
	}
	return result
}

func jsonResult(status int, payload map[string]any) Result {
	body := cloneMap(payload)
	addEnvelope(body)
	raw, _ := json.Marshal(body)
	return Result{StatusCode: status, ContentType: "application/json", Body: raw}
}

func errorResult(status int, code, message string) Result {
	return jsonResult(status, map[string]any{
		"error_code": code,
		"error":      message,
	})
}

func envelope(payload map[string]any) map[string]any {
	cloned := cloneMap(payload)
	addEnvelope(cloned)
	return cloned
}

func addEnvelope(payload map[string]any) {
	if payload == nil {
		return
	}
	if _, ok := payload["ipc_protocol"]; !ok {
		payload["ipc_protocol"] = IPCProtocol
	}
	if _, ok := payload["ipc_version"]; !ok {
		payload["ipc_version"] = IPCVersion
	}
	if _, ok := payload["ipc_min_supported_version"]; !ok {
		payload["ipc_min_supported_version"] = IPCVersion
	}
	if _, ok := payload["ipc_negotiated_version"]; !ok {
		payload["ipc_negotiated_version"] = IPCVersion
	}
	if _, ok := payload["service_version"]; !ok {
		payload["service_version"] = "service-emulator"
	}
}

func decodeRequestBody(raw []byte) (map[string]any, error) {
	if len(bytes.TrimSpace(raw)) == 0 {
		return map[string]any{}, nil
	}
	var body map[string]any
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	if err := decoder.Decode(&body); err != nil {
		return nil, fmt.Errorf("request body must be a JSON object: %w", err)
	}
	if body == nil {
		return nil, errors.New("request body must be a JSON object")
	}
	if err := ensureJSONEOF(decoder); err != nil {
		return nil, err
	}
	return body, nil
}

func requireEmptyObject(body map[string]any) error {
	if len(body) != 0 {
		return errors.New("request body must be an empty JSON object")
	}
	return nil
}

func requireOnlyKeys(body map[string]any, allowed ...string) error {
	for key := range body {
		if !slices.Contains(allowed, key) {
			return fmt.Errorf("request body contains unsupported field %q", key)
		}
	}
	return nil
}

func sameJSONObject(actual []byte, expected json.RawMessage) bool {
	actualBody, err := decodeRequestBody(actual)
	if err != nil {
		return false
	}
	expectedBody, err := decodeRequestBody(expected)
	if err != nil {
		return false
	}
	actualJSON, _ := json.Marshal(actualBody)
	expectedJSON, _ := json.Marshal(expectedBody)
	return bytes.Equal(actualJSON, expectedJSON)
}

func redactRequest(body map[string]any) map[string]any {
	redacted := cloneMap(body)
	for _, key := range []string{"enroll_token", "private_key", "authorization"} {
		if _, ok := redacted[key]; ok {
			redacted[key] = "<redacted>"
		}
	}
	return redacted
}

func routeKey(method, path string) string {
	return strings.ToUpper(strings.TrimSpace(method)) + " " + path
}

func mergeMap(destination, patch map[string]any) {
	for key, value := range patch {
		if value == nil {
			delete(destination, key)
			continue
		}
		patchChild, patchIsMap := value.(map[string]any)
		destinationChild, destinationIsMap := destination[key].(map[string]any)
		if patchIsMap && destinationIsMap {
			mergeMap(destinationChild, patchChild)
			continue
		}
		destination[key] = cloneValue(value)
	}
}

func cloneMap(source map[string]any) map[string]any {
	if source == nil {
		return nil
	}
	cloned, _ := cloneValue(source).(map[string]any)
	return cloned
}

func cloneValue(value any) any {
	raw, err := json.Marshal(value)
	if err != nil {
		return value
	}
	var cloned any
	if err := json.Unmarshal(raw, &cloned); err != nil {
		return value
	}
	return cloned
}

func stringValue(value any) string {
	if value == nil {
		return ""
	}
	return strings.TrimSpace(fmt.Sprint(value))
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}
