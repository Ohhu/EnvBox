//go:build windows

// Package apply turns a stored profile into the live user environment.
//
// Order matters: write the registry, tell Explorer, write the PowerShell snapshot,
// and only then record what was applied. If any step fails the vault is left
// untouched so the UI can retry without lying about the current state.
package apply

import (
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/Ohhu/EnvBox/internal/apperr"
	"github.com/Ohhu/EnvBox/internal/model"
	"github.com/Ohhu/EnvBox/internal/shell"
	"github.com/Ohhu/EnvBox/internal/vault"
	"github.com/Ohhu/EnvBox/internal/winsys"
)

// EnvWriter is the registry side; winsys.EnvStore implements it.
type EnvWriter interface {
	Apply(profile model.EnvProfile, previouslyApplied []string) (winsys.ApplyReport, error)
	Remove(names []string) ([]string, error)
}

// Report is the outcome shown to the user.
type Report struct {
	Profile    string   `json:"profile"`
	Applied    []string `json:"applied"`
	Stale      []string `json:"stale"`
	Generation string   `json:"generation"`
	Warnings   []string `json:"warnings,omitempty"`
}

// Service wires the vault, the registry and the shell snapshot together.
type Service struct {
	Store     *vault.Store
	Env       EnvWriter
	Broadcast func() error
	Shell     *shell.Integration
}

// Activate applies the profile identified by id or name (case-insensitive).
func (s *Service) Activate(reference string) (*Report, error) {
	if s.Store == nil || s.Env == nil {
		return nil, errors.New("apply: 服务未初始化")
	}
	payload, err := s.Store.Load()
	if err != nil {
		return nil, err
	}
	profile, err := findProfile(payload, reference)
	if err != nil {
		return nil, err
	}

	// Validate before touching the registry: a bad profile must not half-apply.
	if err := model.ValidateProfile(*profile); err != nil {
		return nil, err
	}

	report := &Report{Profile: profile.Name}
	applied, err := s.Env.Apply(*profile, payload.AppliedKeys)
	if err != nil {
		return nil, err
	}
	report.Applied = applied.Applied
	report.Stale = applied.Stale
	report.Warnings = append(report.Warnings, applied.Warnings...)

	// Broadcast failures are not fatal: the registry is already correct and only
	// already-running processes miss the notification. The call is asynchronous
	// (SendNotifyMessageW returns immediately); the deadline only guards a wedged
	// call so activation cannot hang on it.
	if s.Broadcast != nil {
		if err := broadcastWithDeadline(s.Broadcast, BroadcastTimeout); err != nil {
			report.Warnings = append(report.Warnings, "未能通知已打开的程序："+apperr.User(err))
		}
	}

	if s.Shell != nil {
		if err := s.Shell.WriteActivation(*profile); err != nil {
			report.Warnings = append(report.Warnings, "PowerShell 快照写入失败："+apperr.User(err))
		}
	}

	payload.ActiveProfileID = &profile.ID
	payload.AppliedKeys = applied.Applied
	fingerprint := profile.Fingerprint()
	payload.AppliedFingerprint = &fingerprint
	report.Generation = fingerprint[:12]

	if err := s.Store.Save(payload); err != nil {
		return report, fmt.Errorf("apply: 环境已写入，但记录激活状态失败：%w", err)
	}
	return report, nil
}

// Deactivate removes every variable the last activation wrote.
func (s *Service) Deactivate() (*Report, error) {
	if s.Store == nil || s.Env == nil {
		return nil, errors.New("apply: 服务未初始化")
	}
	payload, err := s.Store.Load()
	if err != nil {
		return nil, err
	}

	report := &Report{}
	removed, err := s.Env.Remove(payload.AppliedKeys)
	if err != nil {
		return report, err
	}
	report.Stale = removed

	if s.Broadcast != nil {
		if err := broadcastWithDeadline(s.Broadcast, BroadcastTimeout); err != nil {
			report.Warnings = append(report.Warnings, "未能通知已打开的程序："+apperr.User(err))
		}
	}
	if s.Shell != nil {
		if err := s.Shell.RemoveActivation(); err != nil {
			report.Warnings = append(report.Warnings, "删除 PowerShell 快照失败："+apperr.User(err))
		}
	}

	payload.ActiveProfileID = nil
	payload.AppliedKeys = nil
	payload.AppliedFingerprint = nil
	if err := s.Store.Save(payload); err != nil {
		return report, fmt.Errorf("apply: 变量已移除，但清理激活状态失败：%w", err)
	}
	return report, nil
}

// BroadcastTimeout caps how long activation waits for WM_SETTINGCHANGE delivery.
const BroadcastTimeout = 5 * time.Second

// broadcastWithDeadline runs fn and gives up after d. The broadcast itself is
// asynchronous (SendNotifyMessageW), so the deadline only guards a wedged call:
// the registry is already updated and the caller must not hang on it.
func broadcastWithDeadline(fn func() error, d time.Duration) error {
	done := make(chan error, 1)
	go func() { done <- fn() }()
	select {
	case err := <-done:
		return err
	case <-time.After(d):
		return fmt.Errorf("等待送达超时（%s）", d)
	}
}

// findProfile resolves an id or name reference.
func findProfile(payload *model.VaultPayload, reference string) (*model.EnvProfile, error) {
	reference = strings.TrimSpace(reference)
	if reference == "" {
		if active := payload.ActiveProfile(); active != nil {
			return active, nil
		}
		return nil, errors.New("apply: 没有指定配置，且当前没有激活的配置")
	}
	for i := range payload.Profiles {
		if strings.EqualFold(payload.Profiles[i].ID, reference) {
			return &payload.Profiles[i], nil
		}
	}
	for i := range payload.Profiles {
		if strings.EqualFold(strings.TrimSpace(payload.Profiles[i].Name), reference) {
			return &payload.Profiles[i], nil
		}
	}
	return nil, fmt.Errorf("apply: 找不到配置 %q", reference)
}
