package main

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"context"
	"debug/elf"
	"debug/pe"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"
)

type sourceState struct {
	Dirty     bool     `json:"dirty"`
	Paths     []string `json:"dirty_paths"`
	Truncated bool     `json:"dirty_paths_truncated"`
}
type identity struct {
	Repository   string `json:"repository"`
	Commit       string `json:"commit"`
	Archive      string `json:"archive"`
	SHA          string `json:"sha256"`
	Target       string `json:"target"`
	Flutter      string `json:"flutter,omitempty"`
	Dart         string `json:"dart,omitempty"`
	ClientTag    string `json:"client_tag,omitempty"`
	ClientCommit string `json:"client_commit,omitempty"`
	sourceState
}

func (r runner) state(ctx context.Context) (sourceState, error) {
	state := sourceState{Paths: []string{}}
	status, err := r.output(ctx, "git", "status", "--porcelain=v1", "--untracked-files=normal")
	if err != nil || status == "" {
		return state, err
	}
	state.Dirty = true
	for line := range strings.SplitSeq(status, "\n") {
		if len(state.Paths) == 40 {
			state.Truncated = true
			break
		}
		characters := []rune(line)
		if len(characters) > 300 {
			characters = characters[:300]
			state.Truncated = true
		}
		state.Paths = append(state.Paths, string(characters))
	}
	fmt.Fprintln(os.Stderr, "GIT_SOURCE_DIRTY", state.Paths)
	if os.Getenv("GITHUB_ACTIONS") == "true" {
		return state, errors.New("CI checkout has changed")
	}
	return state, nil
}

func (r runner) writeIdentity(ctx context.Context, file, target string, pin *installer) error {
	value := identity{Repository: repository, Archive: filepath.Base(file), Target: target}
	var err error
	value.sourceState, err = r.state(ctx)
	if err != nil {
		return err
	}
	value.Commit, err = r.output(ctx, "git", "rev-parse", "HEAD")
	if err != nil {
		return err
	}
	value.SHA, err = digest(file)
	if err != nil {
		return err
	}
	if pin != nil {
		value.ClientTag, value.ClientCommit = pin.ClientTag, pin.ClientCommit
	} else {
		value.Flutter, value.Dart = flutterVersion, dartVersion
		checksum := value.SHA + "  " + value.Archive + "\n"
		if err := os.WriteFile(file+".sha256", []byte(checksum), 0o644); err != nil {
			return err
		}
	}
	return writeJSON(file+".json", value)
}

func (r runner) build(ctx context.Context, p profile, key, out string) error {
	var a artifact
	for _, candidate := range p.Artifacts {
		if candidate.Target.key() == key {
			a = candidate
			break
		}
	}
	if a.Name == "" || a.Target.OS != runtime.GOOS {
		return errors.New("desktop target must build on its native OS")
	}
	if _, err := r.state(ctx); err != nil {
		return err
	}
	if err := r.verifyFlutter(ctx); err != nil {
		return err
	}
	app := filepath.Join(r.root, a.Module)
	if err := r.exec(ctx, app, nil, "flutter", "pub", "get", "--enforce-lockfile"); err != nil {
		return err
	}
	platform := a.Target.OS
	var env, options []string
	installerTag := ""
	switch platform {
	case "windows":
		var err error
		installerTag, options, err = windowsVersion(app, os.Getenv("GITHUB_REF"))
		if err != nil {
			return err
		}
	case "darwin":
		platform = "macos"
		architecture := "arm64"
		if a.Target.Arch == "amd64" {
			architecture = "x86_64"
		}
		env = []string{"FLUTTER_XCODE_ARCHS=" + architecture, "FLUTTER_XCODE_CODE_SIGNING_ALLOWED=NO"}
	}
	if err := r.exec(ctx, app, env, append([]string{"flutter", "build", platform, "--release", "--no-pub"}, options...)...); err != nil {
		return err
	}
	source := filepath.Join(app, "build/linux/x64/release/bundle")
	binary := filepath.Join(source, "endlessnet_client_ui")
	include := ""
	switch a.Target.OS {
	case "windows":
		source = filepath.Join(app, "build/windows/x64/runner/Release")
		binary = filepath.Join(source, "endlessnet_client_ui.exe")
	case "darwin":
		source = filepath.Join(app, "build/macos/Build/Products/Release")
		bundles, err := filepath.Glob(filepath.Join(source, "*.app"))
		if err != nil {
			return err
		}
		if len(bundles) != 1 {
			return errors.New("expected one macOS app bundle")
		}
		include = filepath.Base(bundles[0])
		binary = filepath.Join(bundles[0], "Contents/MacOS/endlessnet_client_ui")
	}
	if err := r.verifyBinary(ctx, binary, a.Target); err != nil {
		return err
	}
	if err := os.MkdirAll(out, 0o755); err != nil {
		return err
	}
	if a.Target.OS == "windows" {
		if err := r.buildInstaller(ctx, source, out, installerTag, p.Installer); err != nil {
			return err
		}
	}
	if _, err := r.state(ctx); err != nil {
		return err
	}
	file := filepath.Join(out, a.archive())
	if err := writeArchive(source, include, file, a.Target.OS == "windows"); err != nil {
		return err
	}
	return r.writeIdentity(ctx, file, a.Target.key(), nil)
}

func windowsVersion(app, ref string) (string, []string, error) {
	if tag, ok := strings.CutPrefix(ref, "refs/tags/"); ok {
		if !releaseTag.MatchString(tag) {
			return "", nil, errors.New("the Windows version requires an ordinary v0 tag")
		}
		return tag, []string{"--build-name=" + tag[1:]}, nil
	}
	manifest, err := textFile(filepath.Join(app, "pubspec.yaml"))
	if err != nil {
		return "", nil, err
	}
	match := regexp.MustCompile("(?m)^version: ([0-9]+[.][0-9]+[.][0-9]+)").FindStringSubmatch(manifest)
	if len(match) != 2 || !releaseTag.MatchString("v"+match[1]) {
		return "", nil, errors.New("app manifest requires an ordinary v0 version")
	}
	return "v" + match[1], nil, nil
}

func (r runner) verifyBinary(ctx context.Context, binary string, t target) error {
	switch t.OS {
	case "windows":
		file, err := pe.Open(binary)
		if err != nil {
			return err
		}
		if err := file.Close(); err != nil {
			return err
		}
		if file.Machine != pe.IMAGE_FILE_MACHINE_AMD64 {
			return errors.New("expected Windows amd64 PE")
		}
	case "linux":
		file, err := elf.Open(binary)
		if err != nil {
			return err
		}
		if err := file.Close(); err != nil {
			return err
		}
		if file.Machine != elf.EM_X86_64 || file.Class != elf.ELFCLASS64 {
			return errors.New("expected Linux amd64 ELF")
		}
	default:
		arch, err := r.output(ctx, "lipo", "-archs", binary)
		if err != nil {
			return err
		}
		expected := "arm64"
		if t.Arch == "amd64" {
			expected = "x86_64"
		}
		if arch != expected {
			return errors.New("unexpected macOS architecture")
		}
	}
	return nil
}

func walkBundle(root, include string, visit func(path, relative string, info fs.FileInfo, link string) error) error {
	base := root
	if include != "" {
		base = filepath.Join(root, include)
	}
	allowed, err := filepath.EvalSymlinks(base)
	if err != nil {
		return err
	}
	return filepath.WalkDir(base, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		if relative == "." {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		link := ""
		if info.Mode()&os.ModeSymlink != 0 {
			rel, err := filepath.Rel(base, path)
			if err != nil {
				return err
			}
			if _, err := inside(allowed, filepath.ToSlash(rel)); err != nil {
				return err
			}
			link, err = os.Readlink(path)
			if err != nil {
				return err
			}
			if filepath.IsAbs(link) {
				return errors.New("absolute bundle symlink")
			}
		}
		if !info.IsDir() && !info.Mode().IsRegular() && link == "" {
			return errors.New("unsupported bundle file")
		}
		return visit(path, filepath.ToSlash(relative), info, link)
	})
}
func copyFile(dst io.Writer, path string) error {
	src, err := os.Open(path)
	if err != nil {
		return err
	}
	_, err = io.Copy(dst, src)
	return errors.Join(err, src.Close())
}
func writeArchive(root, include, output string, windows bool) error {
	file, err := os.Create(output)
	if err != nil {
		return err
	}
	if windows {
		zipper := zip.NewWriter(file)
		err := walkBundle(root, include, func(path, name string, info fs.FileInfo, link string) error {
			if info.IsDir() {
				return nil
			}
			if link != "" {
				return errors.New("the Windows bundle cannot contain a symlink")
			}
			h := zip.FileHeader{Name: name, Method: zip.Deflate, Modified: time.Date(1980, 1, 1, 0, 0, 0, 0, time.UTC)}
			h.SetMode(0o644)
			target, err := zipper.CreateHeader(&h)
			if err != nil {
				return err
			}
			return copyFile(target, path)
		})
		return errors.Join(err, zipper.Close(), file.Close())
	}
	gz := gzip.NewWriter(file)
	tarball := tar.NewWriter(gz)
	err = walkBundle(root, include, func(path, name string, info fs.FileInfo, link string) error {
		header, err := tar.FileInfoHeader(info, link)
		if err != nil {
			return err
		}
		header.Name = name
		header.Uid, header.Gid, header.Uname, header.Gname = 0, 0, "", ""
		header.ModTime, header.AccessTime, header.ChangeTime = time.Unix(0, 0), time.Time{}, time.Time{}
		header.Format = tar.FormatPAX
		if link == "" {
			header.Mode = 0o644
			if info.IsDir() || info.Mode().Perm()&0o111 != 0 {
				header.Mode = 0o755
			}
		}
		if err := tarball.WriteHeader(header); err != nil {
			return err
		}
		if info.Mode().IsRegular() {
			return copyFile(tarball, path)
		}
		return nil
	})
	return errors.Join(err, tarball.Close(), gz.Close(), file.Close())
}

func (r runner) buildInstaller(ctx context.Context, ui, out, tag string, pin installer) error {
	if err := r.verifyLatestClient(ctx, pin); err != nil {
		return err
	}
	name := "client-" + pin.ClientTag + "-windows-amd64.zip"
	var release releaseInfo
	if err := r.api(ctx, "repos/endless-net/client/releases/tags/"+pin.ClientTag, &release); err != nil {
		return err
	}
	if release.Draft || release.Prerelease || release.Tag != pin.ClientTag {
		return errors.New("the pinned Client release is not published")
	}
	var asset releaseAsset
	for _, candidate := range release.Assets {
		if candidate.Name == name {
			asset = candidate
			break
		}
	}
	const maxSize = 1024 * 1024 * 1024
	if asset.Size <= 0 || asset.Size > maxSize {
		return errors.New("invalid Client archive size")
	}
	tmp, err := os.MkdirTemp("", "client-ui-installer-")
	if err != nil {
		return err
	}
	defer cleanup(tmp)
	if err := r.exec(ctx, r.root, nil, "gh", "release", "download", pin.ClientTag, "--repo", "endless-net/client",
		"--pattern", name, "--pattern", "source.json", "--dir", tmp); err != nil {
		return err
	}
	archiveFile := filepath.Join(tmp, name)
	info, err := os.Stat(archiveFile)
	if err != nil {
		return err
	}
	hash, err := digest(archiveFile)
	if err != nil {
		return err
	}
	if info.Size() != asset.Size || asset.Digest != "sha256:"+hash {
		return errors.New("downloaded Client runtime asset digest or size differs")
	}
	var source struct{ Commit, Tag string }
	if err := readJSON(filepath.Join(tmp, "source.json"), &source); err != nil {
		return err
	}
	if source.Commit != pin.ClientCommit || source.Tag != pin.ClientTag {
		return errors.New("downloaded Client runtime is not the pinned producer commit")
	}
	client := filepath.Join(tmp, "client")
	if err := extractClient(archiveFile, client, maxSize); err != nil {
		return err
	}
	if err := r.exec(ctx, r.root, nil, "pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-File",
		filepath.Join(r.root, "scripts", "build-windows-installer.ps1"), "-UIBundle", ui, "-ClientBundle", client, "-Version", tag, "-OutputDir", out); err != nil {
		return err
	}
	return r.writeIdentity(ctx, filepath.Join(out, pin.filename(tag)), "windows-installer", &pin)
}

func extractClient(file, dest string, maxSize uint64) (err error) {
	archive, err := zip.OpenReader(file)
	if err != nil {
		return err
	}
	defer func() { err = errors.Join(err, archive.Close()) }()
	seen := make(map[string]bool)
	total := uint64(0)
	for _, entry := range archive.File {
		name := strings.TrimSuffix(entry.Name, "/")
		key := strings.ToLower(name)
		if !fs.ValidPath(name) || name == "." || strings.ContainsAny(name, "\\:") || seen[key] ||
			entry.Mode()&os.ModeSymlink != 0 || entry.UncompressedSize64 > maxSize-total {
			return errors.New("unsafe Client archive entry")
		}
		seen[key] = true
		total += entry.UncompressedSize64
		path := filepath.Join(dest, name)
		if entry.FileInfo().IsDir() {
			if err := os.MkdirAll(path, 0o755); err != nil {
				return err
			}
			continue
		}
		if !entry.Mode().IsRegular() {
			return errors.New("unsupported Client archive entry")
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return err
		}
		if err := extractFile(entry, path); err != nil {
			return err
		}
	}
	return nil
}
func extractFile(entry *zip.File, path string) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		return err
	}
	reader, err := entry.Open()
	if err != nil {
		return errors.Join(err, file.Close())
	}
	_, err = io.Copy(file, reader)
	return errors.Join(err, reader.Close(), file.Close())
}
