package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"slices"
	"strings"
)

const repository = "endless-net/client-ui"
const flutterVersion = "3.47.7"
const flutterRevision = "abaf9c523780a608bd46686fd5e53740a07077f8"
const dartVersion = "3.13.5"

var targets = []string{"linux-amd64", "windows-amd64", "darwin-amd64", "darwin-arm64"}
var releaseTag = regexp.MustCompile("^v0[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$")
var commitSHA = regexp.MustCompile("^[0-9a-f]{40}$")
var assetName = regexp.MustCompile("^[a-z0-9][a-z0-9-]*$")

type runner struct {
	root string
	run  func(context.Context, string, []string, ...string) ([]byte, error)
}

func runCommand(ctx context.Context, dir string, env []string, args ...string) ([]byte, error) {
	fmt.Fprintln(os.Stderr, "+", strings.Join(args, " "))
	command := args
	if runtime.GOOS == "windows" && (args[0] == "flutter" || args[0] == "dart") {
		command = append([]string{"cmd.exe", "/d", "/c"}, args...)
	}
	cmd := exec.CommandContext(ctx, command[0], command[1:]...)
	cmd.Dir = dir
	cmd.Env = append(cmd.Environ(), env...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return out, fmt.Errorf("%s: %w\n%s%s", args[0], err, out, stderr.Bytes())
	}
	if stderr.Len() != 0 {
		fmt.Fprint(os.Stderr, stderr.String())
	}
	return out, nil
}

func (r runner) output(ctx context.Context, args ...string) (string, error) {
	data, err := r.run(ctx, r.root, nil, args...)
	return strings.TrimSpace(string(data)), err
}

func (r runner) exec(ctx context.Context, where string, env []string, args ...string) error {
	data, err := r.run(ctx, where, env, args...)
	if err != nil {
		return err
	}
	fmt.Print(string(data))
	return nil
}

type module struct {
	Path, Kind string
	Unit       []string
}
type target struct{ OS, Arch string }

func (t target) key() string { return t.OS + "-" + t.Arch }

type artifact struct {
	Release, Kind, Name, Module string
	Target                      target
}

func (a artifact) archive() string {
	if a.Target.OS == "windows" {
		return a.Name + ".zip"
	}
	return a.Name + ".tar.gz"
}

type installer struct {
	Name         string
	ClientTag    string `json:"client_tag"`
	ClientCommit string `json:"client_commit"`
}

func (i installer) filename(tag string) string { return strings.ReplaceAll(i.Name, "{tag}", tag) }

type profile struct {
	Schema    int
	Component string
	Modules   []module
	Artifacts []artifact
	Installer installer
}

func digest(name string) (string, error) {
	file, err := os.Open(name)
	if err != nil {
		return "", err
	}
	hash := sha256.New()
	_, err = io.Copy(hash, file)
	return fmt.Sprintf("%x", hash.Sum(nil)), errors.Join(err, file.Close())
}
func readJSON(path string, value any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, value)
}
func writeJSON(path string, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0o644)
}
func cleanup(path string) {
	if err := os.RemoveAll(path); err != nil {
		fmt.Fprintln(os.Stderr, err)
	}
}

func inside(root, value string) (string, error) {
	if value == "" || filepath.IsAbs(value) || strings.ContainsAny(value, "\\:") ||
		slices.Contains(strings.Split(value, "/"), "..") {
		return "", errors.New("expected checkout-relative path")
	}
	resolved, err := filepath.EvalSymlinks(filepath.Join(root, value))
	if err != nil {
		return "", err
	}
	rel, err := filepath.Rel(root, resolved)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", errors.New("path escapes checkout")
	}
	return resolved, nil
}

func loadProfile(root string) (profile, error) {
	var p profile
	if err := readJSON(filepath.Join(root, ".ci/profile.json"), &p); err != nil {
		return p, err
	}
	if p.Schema != 1 || p.Component != "client-ui" || len(p.Modules) != 2 ||
		p.Modules[0].Kind != "flutter" || p.Modules[0].Unit == nil ||
		p.Modules[1].Kind != "go" || p.Modules[1].Path != "." || len(p.Modules[1].Unit) != 0 {
		return p, errors.New("invalid Client UI profile")
	}
	if _, err := inside(root, "go.mod"); err != nil {
		return p, err
	}
	app, err := inside(root, p.Modules[0].Path)
	if err != nil {
		return p, err
	}
	for _, entry := range append([]string{"pubspec.yaml", "pubspec.lock"}, p.Modules[0].Unit...) {
		path, err := inside(app, entry)
		if err != nil {
			return p, err
		}
		info, err := os.Stat(path)
		if err != nil {
			return p, err
		}
		if !info.Mode().IsRegular() {
			return p, fmt.Errorf("expected regular module input %s", entry)
		}
	}
	seen, names := make(map[string]bool), make(map[string]bool)
	for _, a := range p.Artifacts {
		key := a.Target.key()
		if !slices.Contains(targets, key) || seen[key] || a.Release != "runtime" || a.Kind != "flutter-desktop" ||
			a.Module != p.Modules[0].Path || !assetName.MatchString(a.Name) || names[a.Name] {
			return p, errors.New("invalid or duplicate desktop artifact")
		}
		seen[key], names[a.Name] = true, true
	}
	if len(seen) != len(targets) || p.Installer.Name != "EndlessNet-{tag}-windows-amd64.msi" ||
		!releaseTag.MatchString(p.Installer.ClientTag) || !commitSHA.MatchString(p.Installer.ClientCommit) {
		return p, errors.New("profile requires four targets and an exact Client installer pin")
	}
	return p, nil
}

func execute(ctx context.Context, args []string) error {
	if len(args) == 0 {
		return errors.New("expected check, library, build or publish")
	}
	flags := flag.NewFlagSet(args[0], flag.ContinueOnError)
	root := flags.String("root", ".", "checkout root")
	out := flags.String("out", ".artifacts", "output directory")
	target := flags.String("target", "", "native desktop target")
	design := flags.Bool("design", false, "run the separate component design suite")
	if err := flags.Parse(args[1:]); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("unexpected positional arguments")
	}
	base, err := filepath.Abs(*root)
	if err != nil {
		return err
	}
	base, err = filepath.EvalSymlinks(base)
	if err != nil {
		return err
	}
	r := runner{root: base, run: runCommand}
	if args[0] == "library" {
		return r.checkLibrary(ctx, *design)
	}
	p, err := loadProfile(base)
	if err != nil {
		return err
	}
	output := *out
	if !filepath.IsAbs(output) {
		output = filepath.Join(base, output)
	}
	switch args[0] {
	case "check":
		return r.check(ctx, p)
	case "build":
		return r.build(ctx, p, *target, output)
	case "publish":
		return r.publish(ctx, p, output)
	default:
		return errors.New("expected check, library, build or publish")
	}
}

func main() {
	if err := execute(context.Background(), os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "CI_FAILED:", err)
		os.Exit(1)
	}
}
