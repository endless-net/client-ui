package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
)

func (r runner) verifyFlutter(ctx context.Context) error {
	pin, err := os.ReadFile(filepath.Join(r.root, ".flutter-version"))
	if err != nil {
		return err
	}
	if strings.TrimSpace(string(pin)) != flutterVersion {
		return errors.New("configured Flutter pin differs from CI")
	}
	if err := r.exec(ctx, r.root, nil, "flutter", "--version"); err != nil {
		return err
	}
	data, err := r.output(ctx, "flutter", "--version", "--machine")
	if err != nil {
		return err
	}
	var actual struct{ FrameworkVersion, FrameworkRevision, DartSDKVersion string }
	if err := json.Unmarshal([]byte(data), &actual); err != nil {
		return err
	}
	if actual.FrameworkVersion != flutterVersion || actual.FrameworkRevision != flutterRevision || actual.DartSDKVersion != dartVersion {
		return errors.New("expected pinned Flutter and Dart SDK")
	}
	return nil
}

var revisionPattern = regexp.MustCompile(`clientApiRevision\s*=\s*'([0-9a-f]{40})'`)
var digestPattern = regexp.MustCompile(`clientContractSha256\s*=\s*'([0-9a-f]{64})'`)

func textFile(path string) (string, error) {
	data, err := os.ReadFile(path)
	return strings.ReplaceAll(string(data), "\r\n", "\n"), err
}
func (r runner) verifyContract(ctx context.Context, app string) error {
	source, err := textFile(filepath.Join(app, "lib/client/contract_identity.dart"))
	if err != nil {
		return err
	}
	revisions, digests := revisionPattern.FindAllStringSubmatch(source, -1), digestPattern.FindAllStringSubmatch(source, -1)
	if len(revisions) != 1 || len(digests) != 1 {
		return errors.New("ambiguous Client contract identity")
	}
	revision, wanted := revisions[0][1], digests[0][1]
	manifest, err := textFile(filepath.Join(app, "pubspec.yaml"))
	if err != nil {
		return err
	}
	if strings.Contains(manifest, "dependency_overrides:") ||
		!regexp.MustCompile("(?m)^      ref: "+revision+"(?: +#.*)?$").MatchString(manifest) {
		return errors.New("the Client SDK manifest pin differs from compiled identity")
	}
	lock, err := textFile(filepath.Join(app, "pubspec.lock"))
	if err != nil {
		return err
	}
	parts := strings.Split("\n"+lock, "\n  endlessnet_client_api:\n")
	if len(parts) != 2 {
		return errors.New("the Client SDK lock entry is missing or ambiguous")
	}
	entry := parts[1]
	if i := regexp.MustCompile("(?m)^(  [a-zA-Z_]|sdks:)").FindStringIndex(entry); i != nil {
		entry = entry[:i[0]]
	}
	for _, pattern := range []string{
		"^      ref: (?:" + revision + "|\"" + revision + "\")$",
		"^      resolved-ref: (?:" + revision + "|\"" + revision + "\")$",
		"^      path: \"api/dart\"$", "^    source: git$",
	} {
		if !regexp.MustCompile("(?m)" + pattern).MatchString(entry) {
			return errors.New("the Client SDK lock differs from compiled identity")
		}
	}
	config := filepath.Join(app, ".dart_tool", "package_config.json")
	var packages struct {
		Packages []struct{ Name, RootURI string }
	}
	if err := readJSON(config, &packages); err != nil {
		return err
	}
	var roots []string
	for _, p := range packages.Packages {
		if p.Name == "endlessnet_client_api" {
			roots = append(roots, p.RootURI)
		}
	}
	if len(roots) != 1 {
		return errors.New("the Client SDK root is ambiguous")
	}
	uri, err := url.Parse(roots[0])
	if err != nil {
		return err
	}
	if uri.Host != "" || (uri.Scheme != "" && uri.Scheme != "file") || uri.Fragment != "" || uri.RawQuery != "" {
		return errors.New("the Client SDK must resolve to a local Git cache")
	}
	name := filepath.FromSlash(uri.Path)
	if uri.Scheme == "" {
		name = filepath.Join(filepath.Dir(config), name)
	}
	if runtime.GOOS == "windows" && uri.Scheme == "file" && len(name) > 2 && name[0] == '\\' && name[2] == ':' {
		name = name[1:]
	}
	sdk, err := filepath.EvalSymlinks(name)
	if err != nil {
		return err
	}
	if filepath.Base(sdk) != "dart" || filepath.Base(filepath.Dir(sdk)) != "api" {
		return errors.New("unexpected Client SDK layout")
	}
	head, err := r.run(ctx, sdk, nil, "git", "rev-parse", "HEAD")
	if err != nil {
		return err
	}
	modified, err := r.run(ctx, sdk, nil, "git", "status", "--porcelain", "--", ".")
	if err != nil {
		return err
	}
	if strings.TrimSpace(string(head)) != revision || len(modified) != 0 {
		return errors.New("the Client SDK cache differs from pinned source")
	}
	actual, err := digest(filepath.Join(filepath.Dir(sdk), "client.binpb"))
	if err != nil {
		return err
	}
	if actual != wanted {
		return errors.New("compiled Client contract digest differs from published descriptor")
	}
	return nil
}

func (r runner) check(ctx context.Context, p profile) error {
	if err := r.verifyFlutter(ctx); err != nil {
		return err
	}
	app := filepath.Join(r.root, p.Modules[0].Path)
	if err := r.exec(ctx, app, nil, "flutter", "pub", "get", "--enforce-lockfile"); err != nil {
		return err
	}
	if err := r.verifyContract(ctx, app); err != nil {
		return err
	}
	for _, args := range [][]string{{"dart", "format", "--output=none", "--set-exit-if-changed", "lib"}, {"flutter", "analyze", "--no-pub"}} {
		if err := r.exec(ctx, app, nil, args...); err != nil {
			return err
		}
	}
	if units := p.Modules[0].Unit; len(units) > 0 {
		if err := r.exec(ctx, app, nil, append([]string{"flutter", "test", "--no-pub"}, units...)...); err != nil {
			return err
		}
	} else {
		fmt.Println("UNIT_ABSENT: no application unit fixtures")
	}
	return nil
}

var ordinaryTest = regexp.MustCompile("^test/[a-z0-9_]+_test[.]dart$")

func libraryUnits(root string) ([]string, error) {
	var p profile
	if err := readJSON(filepath.Join(root, ".ci/profile.json"), &p); err != nil {
		return nil, err
	}
	if p.Schema != 1 || p.Component != "endlessnet-ui" || len(p.Modules) != 1 ||
		p.Modules[0].Path != "." || p.Modules[0].Kind != "flutter" || len(p.Modules[0].Unit) == 0 {
		return nil, errors.New("invalid shared UI library profile")
	}
	declared := make(map[string]bool)
	for _, path := range p.Modules[0].Unit {
		if !ordinaryTest.MatchString(path) || declared[path] {
			return nil, errors.New("expected unique ordinary unit files")
		}
		declared[path] = true
	}
	err := fs.WalkDir(os.DirFS(root), "test", func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !entry.IsDir() && strings.HasSuffix(path, "_test.dart") {
			if !declared[path] {
				return fmt.Errorf("undeclared unit: %s", path)
			}
			delete(declared, path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	if len(declared) != 0 {
		return nil, errors.New("declared unit fixture is missing")
	}
	return p.Modules[0].Unit, nil
}
func (r runner) checkLibrary(ctx context.Context, design bool) error {
	pkg := filepath.Join(r.root, "packages", "endlessnet_ui")
	units, err := libraryUnits(pkg)
	if err != nil {
		return err
	}
	if err := r.verifyFlutter(ctx); err != nil {
		return err
	}
	for _, args := range [][]string{
		{"flutter", "pub", "get", "--enforce-lockfile"},
		{"dart", "format", "--output=none", "--set-exit-if-changed", "lib", "bin", "test", "tool", "test_design"},
		{"flutter", "analyze", "--no-pub"},
	} {
		if err := r.exec(ctx, pkg, nil, args...); err != nil {
			return err
		}
	}
	if design {
		files, err := filepath.Glob(filepath.Join(pkg, "test_design", "components", "*_test.dart"))
		if err != nil {
			return err
		}
		if len(files) == 0 {
			return errors.New("component design suite is absent")
		}
		return r.exec(ctx, pkg, nil, "flutter", "test", "--no-pub", "test_design/components")
	}
	if err := r.exec(ctx, pkg, nil, "dart", "run", "tool/check_test_boundaries.dart"); err != nil {
		return err
	}
	return r.exec(ctx, pkg, nil, append([]string{"flutter", "test", "--no-pub"}, units...)...)
}
