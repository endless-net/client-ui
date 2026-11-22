package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func put(t *testing.T, path, value string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(value), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestWindowsVersion(t *testing.T) {
	root := t.TempDir()
	put(t, filepath.Join(root, "pubspec.yaml"), "version: 0.6.4+1\n")
	tag, args, err := windowsVersion(root, "refs/tags/v0.7.2")
	if tag != "v0.7.2" || !slices.Equal(args, []string{"--build-name=0.7.2"}) || err != nil {
		t.Fatalf("%s %v %v", tag, args, err)
	}
	tag, args, err = windowsVersion(root, "refs/heads/main")
	if tag != "v0.6.4" || len(args) != 0 || err != nil {
		t.Fatalf("%s %v %v", tag, args, err)
	}
	if _, _, err := windowsVersion(root, "refs/tags/v0.7.2-rc.1"); err == nil {
		t.Fatal("accepted prerelease tag")
	}
}

func TestReconcileAssets(t *testing.T) {
	expected := map[string]string{"a": "sha-a", "b": "sha-b"}
	for _, tc := range []struct {
		name   string
		assets map[string]string
		draft  bool
		want   []string
		reject bool
	}{
		{"retry", expected, false, nil, false},
		{"partial draft", map[string]string{"a": "sha-a"}, true, []string{"b"}, false},
		{"partial publication", map[string]string{"a": "sha-a"}, false, nil, true},
		{"conflicting bytes", map[string]string{"a": "other"}, true, nil, true},
		{"unexpected asset", map[string]string{"outside": "other"}, true, nil, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			missing, err := reconcileAssets(tc.assets, expected, tc.draft)
			if (err != nil) != tc.reject || !slices.Equal(missing, tc.want) {
				t.Fatalf("%v %v", missing, err)
			}
		})
	}
}

func TestDirtyAndWrongInstaller(t *testing.T) {
	dir := t.TempDir()
	name := "EndlessNet-v0.6.4-windows-amd64.msi"
	path := filepath.Join(dir, name)
	put(t, path, "fixture")
	hash, err := digest(path)
	if err != nil {
		t.Fatal(err)
	}
	head := strings.Repeat("a", 40)
	pin := installer{ClientTag: "v0.14.3", ClientCommit: strings.Repeat("b", 40)}
	i := identity{Repository: repository, Commit: head, Archive: name, SHA: hash, Target: "windows-installer",
		ClientTag: pin.ClientTag, ClientCommit: pin.ClientCommit, sourceState: sourceState{Paths: []string{}}}
	check := func(want bool) {
		t.Helper()
		if err := writeJSON(path+".json", i); err != nil {
			t.Fatal(err)
		}
		if _, err := verifyArtifact(dir, name, head, "windows-installer", &pin); (err == nil) != want {
			t.Fatalf("artifact validation: %v", err)
		}
	}
	check(true)
	data, err := os.ReadFile(path + ".json")
	if err != nil {
		t.Fatal(err)
	}
	put(t, path+".json", strings.Replace(string(data), `"dirty":false,`, "", 1))
	if _, err := verifyArtifact(dir, name, head, "windows-installer", &pin); err == nil {
		t.Fatal("accepted an artifact without a checkout status")
	}
	i.Dirty = true
	check(false)
	i.Dirty = false
	i.ClientCommit = head
	check(false)
}

func TestContractIdentity(t *testing.T) {
	root := t.TempDir()
	app := filepath.Join(root, "app")
	sdk := filepath.Join(root, "cache", "api", "dart")
	put(t, filepath.Join(sdk, "sdk.txt"), "test")
	descriptor := filepath.Join(filepath.Dir(sdk), "client.binpb")
	put(t, descriptor, "test descriptor")
	hash, err := digest(descriptor)
	if err != nil {
		t.Fatal(err)
	}
	head := strings.Repeat("a", 40)
	put(t, filepath.Join(app, "lib/client/contract_identity.dart"), "const clientApiRevision = '"+head+"';\nconst clientContractSha256 = '"+hash+"';\n")
	put(t, filepath.Join(app, "pubspec.yaml"), "      ref: "+head+"\n")
	lock := filepath.Join(app, "pubspec.lock")
	contents := "packages:\n  endlessnet_client_api:\n    description:\n      path: \"api/dart\"\n      ref: " + head + "\n      resolved-ref: " + head + "\n    source: git\nsdks:\n"
	put(t, lock, contents)
	name := filepath.ToSlash(sdk)
	if !strings.HasPrefix(name, "/") {
		name = "/" + name
	}
	uri := url.URL{Scheme: "file", Path: name + "/"}
	config, err := json.Marshal(map[string]any{"packages": []map[string]string{{"name": "endlessnet_client_api", "rootUri": uri.String()}}})
	if err != nil {
		t.Fatal(err)
	}
	put(t, filepath.Join(app, ".dart_tool/package_config.json"), string(config))
	dirty := false
	r := runner{run: func(_ context.Context, where string, _ []string, args ...string) ([]byte, error) {
		if filepath.Base(where) != "dart" || args[0] != "git" {
			return nil, errors.New("unexpected command")
		}
		if args[1] == "rev-parse" {
			return []byte(head + "\n"), nil
		}
		if dirty {
			return []byte(" M sdk.txt\n"), nil
		}
		return nil, nil
	}}
	check := func(want bool) {
		t.Helper()
		if err := r.verifyContract(t.Context(), app); (err == nil) != want {
			t.Fatalf("contract check: %v", err)
		}
	}
	check(true)
	dirty = true
	check(false)
	dirty = false
	put(t, lock, strings.Replace(contents, "resolved-ref: "+head, "resolved-ref: "+strings.Repeat("b", 40), 1))
	check(false)
	put(t, lock, contents)
	put(t, descriptor, "mutated")
	check(false)
}

func TestLibraryInventory(t *testing.T) {
	root := t.TempDir()
	put(t, filepath.Join(root, ".ci/profile.json"), `{"schema":1,"component":"endlessnet-ui","modules":[{"path":".","kind":"flutter","unit":["test/widget_test.dart"]}]}`)
	put(t, filepath.Join(root, "test/widget_test.dart"), "")
	put(t, filepath.Join(root, "test_design/components/design_test.dart"), "")
	if _, err := libraryUnits(root); err != nil {
		t.Fatal(err)
	}
	put(t, filepath.Join(root, "test/extra_test.dart"), "")
	if _, err := libraryUnits(root); err == nil {
		t.Fatal("accepted undeclared unit test")
	}
}
