package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

type releaseAsset struct {
	Name, Digest string
	Size         int64
}
type releaseInfo struct {
	Tag        string `json:"tag_name"`
	Commit     string `json:"target_commitish"`
	Draft      bool
	Prerelease bool
	Assets     []releaseAsset
}

func (r runner) api(ctx context.Context, endpoint string, value any) error {
	data, err := r.output(ctx, "gh", "api", endpoint)
	if err != nil {
		return err
	}
	return json.Unmarshal([]byte(data), value)
}
func (r runner) verifyLatestClient(ctx context.Context, pin installer) error {
	var latest releaseInfo
	if err := r.api(ctx, "repos/endless-net/client/releases/latest", &latest); err != nil {
		return err
	}
	if latest.Draft || latest.Prerelease || latest.Tag != pin.ClientTag {
		return errors.New("installer pin is not the latest published stable Client release")
	}
	return nil
}

func (r runner) viewRelease(ctx context.Context, tag string) (releaseInfo, error) {
	var info struct {
		TagName, TargetCommitish string
		IsDraft, IsPrerelease    bool
		Assets                   []releaseAsset
	}
	data, err := r.output(ctx, "gh", "release", "view", tag, "--repo", repository, "--json", "tagName,targetCommitish,isDraft,isPrerelease,assets")
	if err != nil {
		return releaseInfo{}, err
	}
	if err := json.Unmarshal([]byte(data), &info); err != nil {
		return releaseInfo{}, err
	}
	if info.TagName != tag {
		return releaseInfo{}, errors.New("release tag differs")
	}
	return releaseInfo{Tag: tag, Commit: info.TargetCommitish, Draft: info.IsDraft, Prerelease: info.IsPrerelease, Assets: info.Assets}, nil
}

func (r runner) verifyRemoteTag(ctx context.Context, tag, head string) error {
	var ref struct{ Object struct{ Type, SHA string } }
	if err := r.api(ctx, "repos/"+repository+"/git/ref/tags/"+tag, &ref); err != nil {
		return err
	}
	seen := make(map[string]bool)
	for ref.Object.Type == "tag" {
		sha := ref.Object.SHA
		if !commitSHA.MatchString(sha) || seen[sha] || len(seen) >= 8 {
			return errors.New("invalid annotated tag chain")
		}
		seen[sha] = true
		if err := r.api(ctx, "repos/"+repository+"/git/tags/"+sha, &ref); err != nil {
			return err
		}
	}
	if ref.Object.Type != "commit" || ref.Object.SHA != head {
		return errors.New("remote tag does not identify the checked commit")
	}
	return nil
}

func reconcileAssets(existing, expected map[string]string, draft bool) ([]string, error) {
	for name, digest := range existing {
		if expected[name] == "" || expected[name] != digest {
			return nil, fmt.Errorf("release asset differs: %s", name)
		}
	}
	var missing []string
	for _, name := range slices.Sorted(maps.Keys(expected)) {
		if _, found := existing[name]; !found {
			missing = append(missing, name)
		}
	}
	if len(missing) != 0 && !draft {
		return nil, errors.New("published release is incomplete")
	}
	return missing, nil
}
func (r runner) downloadedAssets(ctx context.Context, tag string) (map[string]string, error) {
	directory, err := os.MkdirTemp("", "client-ui-release-")
	if err != nil {
		return nil, err
	}
	defer cleanup(directory)
	if err := r.exec(ctx, r.root, nil, "gh", "release", "download", tag, "--repo", repository, "--dir", directory); err != nil {
		return nil, err
	}
	files, err := os.ReadDir(directory)
	if err != nil {
		return nil, err
	}
	assets := make(map[string]string)
	for _, file := range files {
		hash, err := digest(filepath.Join(directory, file.Name()))
		if err != nil {
			return nil, err
		}
		assets[file.Name()] = hash
	}
	return assets, nil
}
func verifyArtifact(out, name, head, target string, pin *installer) (string, error) {
	path := filepath.Join(out, name)
	var metadata struct {
		identity
		Dirty *bool `json:"dirty"`
	}
	if err := readJSON(path+".json", &metadata); err != nil {
		return "", err
	}
	hash, err := digest(path)
	if err != nil {
		return "", err
	}
	if metadata.Commit != head || metadata.Repository != repository || metadata.Archive != name ||
		metadata.SHA != hash || metadata.Target != target || metadata.Dirty == nil || *metadata.Dirty {
		return "", fmt.Errorf("artifact differs from checked source: %s", name)
	}
	if pin != nil && (metadata.ClientTag != pin.ClientTag || metadata.ClientCommit != pin.ClientCommit) {
		return "", errors.New("installer Client pin differs")
	}
	return hash, nil
}
func msiSize(path string) (int64, error) {
	file, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	var magic [8]byte
	_, err = io.ReadFull(file, magic[:])
	info, statErr := file.Stat()
	if err := errors.Join(err, statErr, file.Close()); err != nil {
		return 0, err
	}
	if !bytes.Equal(magic[:], []byte{0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1}) {
		return 0, errors.New("expected Windows Installer compound file")
	}
	return info.Size(), nil
}

func (r runner) publish(ctx context.Context, p profile, out string) error {
	head, err := r.output(ctx, "git", "rev-parse", "HEAD")
	if err != nil {
		return err
	}
	tag, ok := strings.CutPrefix(os.Getenv("GITHUB_REF"), "refs/tags/")
	if !ok || !releaseTag.MatchString(tag) || os.Getenv("GITHUB_EVENT_NAME") != "push" ||
		os.Getenv("GITHUB_REPOSITORY") != repository || os.Getenv("GITHUB_SHA") != head || !commitSHA.MatchString(head) {
		return errors.New("publication requires an ordinary v0 tag push on the exact source")
	}
	if err := r.verifyRemoteTag(ctx, tag, head); err != nil {
		return err
	}
	pin := p.Installer
	if err := r.verifyLatestClient(ctx, pin); err != nil {
		return err
	}
	assets := make(map[string]string)
	for _, a := range p.Artifacts {
		name := a.archive()
		hash, err := verifyArtifact(out, name, head, a.Target.key(), nil)
		if err != nil {
			return err
		}
		assets[name] = hash
	}
	msi := pin.filename(tag)
	assets[msi], err = verifyArtifact(out, msi, head, "windows-installer", &pin)
	if err != nil {
		return err
	}
	size, err := msiSize(filepath.Join(out, msi))
	if err != nil {
		return err
	}
	manifest := filepath.Join(out, "windows-update.json")
	signature := filepath.Join(out, "windows-update.p7s")
	if err := writeJSON(manifest, map[string]any{
		"schema": 1, "repository": repository, "version": tag[1:], "commit": head,
		"msi": map[string]any{"sha256": assets[msi], "size": size}, "assets": assets,
	}); err != nil {
		return err
	}
	if err := r.exec(ctx, r.root, nil, "pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-File",
		filepath.Join(r.root, "scripts", "sign-windows-release.ps1"), "-Manifest", manifest, "-Signature", signature); err != nil {
		return err
	}
	for _, name := range []string{manifest, signature} {
		hash, err := digest(name)
		if err != nil {
			return err
		}
		assets[filepath.Base(name)] = hash
	}
	var checksums strings.Builder
	for _, name := range slices.Sorted(maps.Keys(assets)) {
		fmt.Fprintf(&checksums, "%s  %s\n", assets[name], name)
	}
	if err := os.WriteFile(filepath.Join(out, "checksums.txt"), []byte(checksums.String()), 0o644); err != nil {
		return err
	}
	if err := writeJSON(filepath.Join(out, "source.json"), map[string]string{
		"repository": repository, "commit": head, "tag": tag, "flutter": flutterVersion, "dart": dartVersion,
		"client_tag": pin.ClientTag, "client_commit": pin.ClientCommit,
	}); err != nil {
		return err
	}
	for _, name := range []string{"checksums.txt", "source.json"} {
		assets[name], err = digest(filepath.Join(out, name))
		if err != nil {
			return err
		}
	}
	if err := r.publishAssets(ctx, out, tag, head, pin, assets); err != nil {
		return err
	}
	fmt.Println("PUBLISHED", repository, tag, head)
	return nil
}

func (r runner) publishAssets(ctx context.Context, out, tag, head string, pin installer, assets map[string]string) error {
	data, err := r.output(ctx, "gh", "api", "--paginate", "--slurp", "repos/"+repository+"/releases")
	if err != nil {
		return err
	}
	var pages [][]releaseInfo
	if err := json.Unmarshal([]byte(data), &pages); err != nil {
		return err
	}
	var matches []releaseInfo
	for _, page := range pages {
		for _, release := range page {
			if release.Tag == tag {
				matches = append(matches, release)
			}
		}
	}
	if len(matches) > 1 {
		return errors.New("multiple releases have the same tag")
	}
	var release releaseInfo
	if len(matches) == 0 {
		notes := fmt.Sprintf("Source commit: %s\nWindows MSI includes Client %s (%s) and the standard https://endlessnet.ru configuration. Windows updates are authenticated by the EndlessNet release signature (windows-update.p7s).", head, pin.ClientTag, pin.ClientCommit)
		if err := r.exec(ctx, r.root, nil, "gh", "release", "create", tag, "--repo", repository, "--draft", "--verify-tag", "--target", head,
			"--title", tag, "--generate-notes", "--notes", notes); err != nil {
			return err
		}
		release, err = r.viewRelease(ctx, tag)
		if err != nil {
			return err
		}
	} else {
		release = matches[0]
	}
	if release.Prerelease || release.Commit != head {
		return errors.New("existing release has a different identity")
	}
	existing := make(map[string]string)
	if len(release.Assets) > 0 {
		existing, err = r.downloadedAssets(ctx, tag)
		if err != nil {
			return err
		}
		if len(existing) != len(release.Assets) {
			return errors.New("downloaded asset inventory differs from release")
		}
	}
	missing, err := reconcileAssets(existing, assets, release.Draft)
	if err != nil {
		return err
	}
	for _, name := range missing {
		if err := r.exec(ctx, r.root, nil, "gh", "release", "upload", tag, filepath.Join(out, name), "--repo", repository); err != nil {
			return err
		}
	}
	if err := r.verifyRemoteTag(ctx, tag, head); err != nil {
		return err
	}
	if release.Draft {
		verified, err := r.downloadedAssets(ctx, tag)
		if err != nil {
			return err
		}
		if _, err := reconcileAssets(verified, assets, false); err != nil {
			return err
		}
		if err := r.verifyLatestClient(ctx, pin); err != nil {
			return err
		}
		if err := r.exec(ctx, r.root, nil, "gh", "release", "edit", tag, "--repo", repository, "--draft=false"); err != nil {
			return err
		}
	}
	final, err := r.viewRelease(ctx, tag)
	if err != nil {
		return err
	}
	if final.Draft || final.Prerelease || final.Commit != head {
		return errors.New("published state is not confirmed")
	}
	return nil
}
