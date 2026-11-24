package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestPublishDraftAndRetry(t *testing.T) {
	for _, broken := range []bool{false, true} {
		name := "published retry"
		if broken {
			name = "interrupted upload"
		}
		t.Run(name, func(t *testing.T) {
			out := t.TempDir()
			tag, head := "v0.9.1", strings.Repeat("a", 40)
			pin := installer{ClientTag: "v0.14.4", ClientCommit: strings.Repeat("b", 40)}
			expected := make(map[string]string)
			for _, name := range []string{"a.zip", "b.msi"} {
				put(t, filepath.Join(out, name), name)
				hash, err := digest(filepath.Join(out, name))
				if err != nil {
					t.Fatal(err)
				}
				expected[name] = hash
			}
			uploaded := map[string][]byte{}
			var calls []string
			hasRelease, draft := false, false
			r := runner{run: func(_ context.Context, _ string, _ []string, args ...string) ([]byte, error) {
				assets := make([]map[string]string, 0, len(uploaded))
				for name := range uploaded {
					assets = append(assets, map[string]string{"name": name})
				}
				if args[1] == "api" {
					endpoint := args[len(args)-1]
					switch {
					case strings.Contains(endpoint, "git/ref/tags/"):
						return json.Marshal(map[string]any{"object": map[string]string{"type": "commit", "sha": head}})
					case strings.HasSuffix(endpoint, "endless-net/client/releases/latest"):
						return json.Marshal(map[string]any{"tag_name": pin.ClientTag, "draft": false, "prerelease": false})
					case strings.HasSuffix(endpoint, "/releases"):
						if !hasRelease {
							return []byte("[[]]"), nil
						}
						return json.Marshal([][]map[string]any{{{"tag_name": tag, "target_commitish": head, "draft": draft, "prerelease": false, "assets": assets}}})
					}
					t.Fatalf("unexpected API: %v", args)
				}
				switch args[2] {
				case "create":
					calls = append(calls, "create")
					hasRelease, draft = true, true
				case "view":
					return json.Marshal(map[string]any{"tagName": tag, "targetCommitish": head, "isDraft": draft, "isPrerelease": false, "assets": assets})
				case "download":
					dir := args[slices.Index(args, "--dir")+1]
					for name, value := range uploaded {
						put(t, filepath.Join(dir, name), string(value))
					}
				case "upload":
					name := filepath.Base(args[4])
					if name == "b.msi" && broken {
						broken = false
						return nil, errors.New("transient upload failure")
					}
					calls = append(calls, "upload "+name)
					var err error
					uploaded[name], err = os.ReadFile(args[4])
					return nil, err
				case "edit":
					calls = append(calls, "promote")
					draft = false
				default:
					t.Fatalf("unexpected command: %v", args)
				}
				return nil, nil
			}}
			if initiallyBroken := broken; initiallyBroken {
				if err := r.publishAssets(t.Context(), out, tag, head, pin, expected); err == nil || !draft || len(uploaded) != 1 {
					t.Fatalf("failed upload did not leave a resumable draft: %v", err)
				}
			}
			if err := r.publishAssets(t.Context(), out, tag, head, pin, expected); err != nil {
				t.Fatal(err)
			}
			if err := r.publishAssets(t.Context(), out, tag, head, pin, expected); err != nil {
				t.Fatal(err)
			}
			if draft || !slices.Equal(calls, []string{"create", "upload a.zip", "upload b.msi", "promote"}) {
				t.Fatalf("unexpected mutations: %v", calls)
			}
		})
	}
}
