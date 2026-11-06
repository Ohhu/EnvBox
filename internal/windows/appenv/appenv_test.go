//go:build windows

package appenv

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Ohhu/EnvBox/internal/core/model"
	"github.com/Ohhu/EnvBox/internal/windows/vault"
)

func newProvider(t *testing.T) *Provider {
	t.Helper()
	dir := t.TempDir()
	store := &vault.Store{Path: filepath.Join(dir, "vault.envbox"), Provider: &vault.MemoryProvider{ID: "k1"}}
	payload := model.EmptyVaultPayload(model.Now())
	fingerprint := "deadbeefcafe0000"
	payload.Profiles = []model.EnvProfile{{
		ID: "p1", Name: "工作",
		Variables: []model.EnvVariable{
			{ID: "a", Key: "ENVBOX_ALPHA", Value: "alpha-value", IsEnabled: true},
			{ID: "b", Key: "ENVBOX_SECRET", Value: "s3cret-value", IsEnabled: true, IsSecret: true},
			{ID: "c", Key: "ENVBOX_OFF", Value: "ignored", IsEnabled: false},
		},
	}}
	payload.ActiveProfileID = ptr("p1")
	payload.AppliedFingerprint = &fingerprint
	if err := store.Save(payload); err != nil {
		t.Fatalf("seed vault: %v", err)
	}
	return &Provider{Store: store, MaxOutputBytes: 4096}
}

func ptr[T any](v T) *T { return &v }

func TestDescribeHidesValues(t *testing.T) {
	p := newProvider(t)
	desc, err := p.Describe(nil)
	if err != nil {
		t.Fatalf("describe: %v", err)
	}
	if !desc.Available || desc.Profile != "工作" || desc.Count != 2 {
		t.Fatalf("unexpected description %+v", desc)
	}
	if desc.Generation != "deadbeefcafe" {
		t.Fatalf("generation should come from the applied fingerprint, got %q", desc.Generation)
	}
	for _, v := range desc.Vars {
		if strings.Contains(v.Fingerprint, "alpha") || v.Length == 0 {
			t.Fatalf("description leaks or misreports: %+v", v)
		}
	}

	desc, err = p.Describe([]string{"envbox_alpha", "MISSING_KEY"})
	if err != nil {
		t.Fatal(err)
	}
	if len(desc.Vars) != 1 || desc.Vars[0].Name != "ENVBOX_ALPHA" {
		t.Fatalf("keys lookup must be case-insensitive: %+v", desc.Vars)
	}
	if len(desc.Missing) != 1 || desc.Missing[0] != "MISSING_KEY" {
		t.Fatalf("unexpected missing list %+v", desc.Missing)
	}
}

func TestValueAndMergeEnvironment(t *testing.T) {
	p := newProvider(t)
	value, ok, err := p.Value("envbox_secret")
	if err != nil || !ok || value != "s3cret-value" {
		t.Fatalf("value: ok=%v err=%v", ok, err)
	}
	if _, ok, _ := p.Value("ENVBOX_OFF"); ok {
		t.Fatal("disabled variables must not be visible")
	}

	merged := MergeEnvironment([]string{"PATH=C:\\bin", "ENVBOX_ALPHA=inherited"}, mustActive(t, p))
	joined := strings.Join(merged, "\n")
	if !strings.Contains(joined, "ENVBOX_ALPHA=alpha-value") {
		t.Fatalf("profile must win over the inherited value:\n%s", joined)
	}
	if strings.Count(joined, "ENVBOX_ALPHA=") != 1 {
		t.Fatalf("case-insensitive merge produced duplicates:\n%s", joined)
	}
	if !strings.Contains(joined, "PATH=C:\\bin") {
		t.Fatalf("inherited environment must be preserved:\n%s", joined)
	}
}

func TestExecuteCapturesOutputAndExitCode(t *testing.T) {
	p := newProvider(t)
	result, err := p.Execute(context.Background(), "echo %ENVBOX_ALPHA%", 20*time.Second)
	if err != nil {
		t.Fatalf("execute: %v", err)
	}
	if result.ExitCode != 0 {
		t.Fatalf("exit=%d stderr=%s", result.ExitCode, result.Stderr)
	}
	if !strings.Contains(strings.ToLower(string(result.Stdout)), "alpha-value") {
		t.Fatalf("expected the profile value in stdout, got %q", result.Stdout)
	}

	failing, err := p.Execute(context.Background(), "exit 7", 20*time.Second)
	if err != nil {
		t.Fatalf("execute: %v", err)
	}
	if failing.ExitCode != 7 {
		t.Fatalf("expected exit code 7, got %d", failing.ExitCode)
	}
}

func TestExecuteTruncatesLargeOutput(t *testing.T) {
	p := newProvider(t)
	p.MaxOutputBytes = 128
	result, err := p.Execute(context.Background(), "for /L %i in (1,1,200) do @echo 0123456789", 30*time.Second)
	if err != nil {
		t.Fatalf("execute: %v", err)
	}
	if !result.Truncated {
		t.Fatal("expected truncation flag")
	}
	if len(result.Stdout) > 128 {
		t.Fatalf("stdout exceeded cap: %d", len(result.Stdout))
	}
}

func mustActive(t *testing.T, p *Provider) *model.EnvProfile {
	t.Helper()
	profile, _, err := p.Active()
	if err != nil || profile == nil {
		t.Fatalf("active profile: %v", err)
	}
	return profile
}
