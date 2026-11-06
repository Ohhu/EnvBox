//go:build windows

package apply

import (
	"errors"
	"path/filepath"
	"testing"

	"github.com/Ohhu/EnvBox/internal/model"
	"github.com/Ohhu/EnvBox/internal/vault"
	"github.com/Ohhu/EnvBox/internal/winsys"
)

type fakeEnv struct {
	applied []string
	removed []string
	prev    []string
	failOn  string
}

func (f *fakeEnv) Apply(profile model.EnvProfile, previous []string) (winsys.ApplyReport, error) {
	if f.failOn == "apply" {
		return winsys.ApplyReport{}, errors.New("registry boom")
	}
	f.prev = previous
	for _, v := range profile.EnabledVariables() {
		f.applied = append(f.applied, v.TrimmedKey())
	}
	return winsys.ApplyReport{Applied: f.applied}, nil
}

func (f *fakeEnv) Remove(names []string) ([]string, error) {
	if f.failOn == "remove" {
		return nil, errors.New("registry boom")
	}
	f.removed = append(f.removed, names...)
	return names, nil
}

func newService(t *testing.T) (*Service, *fakeEnv) {
	t.Helper()
	dir := t.TempDir()
	store := &vault.Store{Path: filepath.Join(dir, "vault.envbox"), Provider: &vault.MemoryProvider{ID: "k"}}
	payload := model.EmptyVaultPayload(model.Now())
	payload.Profiles = []model.EnvProfile{
		{
			ID: "AAAAAAAA-0000-4000-8000-000000000001", Name: "工作",
			Variables: []model.EnvVariable{
				{ID: "a", Key: "API_TOKEN", Value: "v1", IsEnabled: true, IsSecret: true},
				{ID: "b", Key: "REGION", Value: "cn", IsEnabled: true},
			},
		},
		{ID: "BBBBBBBB-0000-4000-8000-000000000002", Name: "个人", Variables: []model.EnvVariable{
			{ID: "c", Key: "LOCALE", Value: "zh-CN", IsEnabled: true},
		}},
	}
	if err := store.Save(payload); err != nil {
		t.Fatal(err)
	}
	env := &fakeEnv{}
	return &Service{Store: store, Env: env, Broadcast: func() error { return nil }}, env
}

func TestActivateRecordsState(t *testing.T) {
	service, env := newService(t)
	report, err := service.Activate("工作")
	if err != nil {
		t.Fatalf("activate: %v", err)
	}
	if len(report.Applied) != 2 || report.Generation == "" {
		t.Fatalf("unexpected report %+v", report)
	}

	payload, err := service.Store.Load()
	if err != nil {
		t.Fatal(err)
	}
	if payload.ActiveProfileID == nil || *payload.ActiveProfileID != "AAAAAAAA-0000-4000-8000-000000000001" {
		t.Fatalf("active profile not recorded: %+v", payload.ActiveProfileID)
	}
	if len(payload.AppliedKeys) != 2 {
		t.Fatalf("applied keys not recorded: %v", payload.AppliedKeys)
	}

	// Switching profiles must tell the writer what was previously applied so the
	// registry can prune stale keys.
	service.Activate("个人")
	if len(env.prev) != 2 {
		t.Fatalf("previous keys not forwarded: %v", env.prev)
	}
}

func TestActivateRejectsUnknownProfile(t *testing.T) {
	service, _ := newService(t)
	if _, err := service.Activate("不存在的配置"); err == nil {
		t.Fatal("expected unknown profile to fail")
	}
}

func TestRegistryFailureLeavesVaultUntouched(t *testing.T) {
	service, env := newService(t)
	env.failOn = "apply"
	if _, err := service.Activate("工作"); err == nil {
		t.Fatal("expected failure")
	}
	payload, _ := service.Store.Load()
	if payload.ActiveProfileID != nil || len(payload.AppliedKeys) != 0 {
		t.Fatalf("vault must not record a failed activation: %+v", payload)
	}
}

func TestBroadcastFailureIsAWarningNotAnError(t *testing.T) {
	service, _ := newService(t)
	service.Broadcast = func() error { return errors.New("no explorer") }
	report, err := service.Activate("工作")
	if err != nil {
		t.Fatalf("broadcast failure must not abort: %v", err)
	}
	if len(report.Warnings) == 0 {
		t.Fatal("expected a warning")
	}
}

func TestDeactivateClearsState(t *testing.T) {
	service, env := newService(t)
	if _, err := service.Activate("工作"); err != nil {
		t.Fatal(err)
	}
	report, err := service.Deactivate()
	if err != nil {
		t.Fatalf("deactivate: %v", err)
	}
	if len(report.Stale) != 2 || len(env.removed) != 2 {
		t.Fatalf("unexpected removals: %+v / %v", report.Stale, env.removed)
	}
	payload, _ := service.Store.Load()
	if payload.ActiveProfileID != nil || len(payload.AppliedKeys) != 0 || payload.AppliedFingerprint != nil {
		t.Fatalf("state not cleared: %+v", payload)
	}
}
