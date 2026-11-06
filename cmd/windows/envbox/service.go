//go:build windows

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/Ohhu/EnvBox/internal/core/apperr"
	"github.com/Ohhu/EnvBox/internal/core/buildinfo"
	"github.com/Ohhu/EnvBox/internal/core/model"
	"github.com/Ohhu/EnvBox/internal/core/portable"
	"github.com/Ohhu/EnvBox/internal/windows/apply"
	"github.com/Ohhu/EnvBox/internal/windows/mcp"
	"github.com/Ohhu/EnvBox/internal/windows/settings"
	"github.com/Ohhu/EnvBox/internal/windows/shell"
	"github.com/Ohhu/EnvBox/internal/windows/update"
	"github.com/Ohhu/EnvBox/internal/windows/vault"
	"github.com/Ohhu/EnvBox/internal/windows/winsys"
)

// App is the single service the frontend talks to. Everything travels through
// Dispatch with a JSON payload so the binding surface stays two methods wide.
type App struct {
	// vaultMu serialises vault read-modify-write cycles: the JSON API serves
	// requests concurrently and every profile mutation is load → edit → save.
	// Long operations (update download, installer launch) stay outside it so the
	// UI can still read state while they run.
	vaultMu sync.Mutex
	store   *vault.Store
	env     envStore
	shell   *shell.Integration
	notify  func(string)
}

// envStore is the slice of the user environment the service needs. Keeping it
// behind an interface lets tests exercise apply/delete without writing HKCU.
type envStore interface {
	List() ([]winsys.EnvEntry, error)
	Apply(profile model.EnvProfile, previouslyApplied []string) (winsys.ApplyReport, error)
	Remove(names []string) ([]string, error)
}

// NewApp wires the service.
func NewApp(notify func(string)) (*App, error) {
	store, err := vault.NewStore()
	if err != nil {
		return nil, err
	}
	integration, err := shell.New()
	if err != nil {
		return nil, err
	}
	return &App{store: store, env: winsys.NewConfigurableEnvStore(), shell: integration, notify: notify}, nil
}

// maskedValue is what the list view shows for a secret. Posting it back must be
// read as "unchanged", not "replace the secret with bullets".
const maskedValue = "••••••••"

// ProfileView is one profile row.
type ProfileView struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Note      string    `json:"note"`
	Tint      string    `json:"tint"`
	Symbol    string    `json:"symbol"`
	Variables []VarView `json:"variables"`
	Secrets   int       `json:"secrets"`
	Enabled   int       `json:"enabled"`
	Active    bool      `json:"active"`
	// UpdatedAt lets both UIs render the same "last modified" stat; the macOS
	// side already carries it on EnvProfile.
	UpdatedAt string `json:"updatedAt"`
}

// VarView is one variable row. Secret values are masked unless reveal is asked for.
type VarView struct {
	ID      string `json:"id"`
	Key     string `json:"key"`
	Value   string `json:"value"`
	Masked  bool   `json:"masked"`
	Enabled bool   `json:"enabled"`
	Secret  bool   `json:"secret"`
	Note    string `json:"note"`
}

// SystemVariable is one entry of the live user environment.
type SystemVariable struct {
	Key       string `json:"key"`
	Value     string `json:"value"`
	Kind      string `json:"kind"`
	Sensitive bool   `json:"sensitive"`
	Applied   bool   `json:"applied"`
}

// SettingsView is the editable settings payload.
type SettingsView struct {
	Check          string `json:"check"`
	SkippedVersion string `json:"skippedVersion"`
	LastCheckAt    string `json:"lastCheckAt"`
	LastResult     string `json:"lastResult"`
}

// UpdateView describes the updater state shown in the UI.
type UpdateView struct {
	HTMLURL   string `json:"htmlUrl,omitempty"`
	Current   string `json:"current"`
	Available string `json:"available,omitempty"`
	Notes     string `json:"notes,omitempty"`
	Pending   string `json:"pending,omitempty"`
	// PendingError reports an unreadable handoff record; without it the install
	// button would just vanish.
	PendingError string `json:"pendingError,omitempty"`
	Signing      bool   `json:"signing"`
	CanInstall   bool   `json:"canInstall"`
}

// StateView is everything the first render needs.
type StateView struct {
	Version     string           `json:"version"`
	Channel     string           `json:"channel"`
	Installed   bool             `json:"installed"`
	Profiles    []ProfileView    `json:"profiles"`
	ActiveID    string           `json:"activeId"`
	AppliedKeys []string         `json:"appliedKeys"`
	System      []SystemVariable `json:"system"`
	Settings    SettingsView     `json:"settings"`
	Update      UpdateView       `json:"update"`
	Shell       shell.Status     `json:"shell"`
	Autostart   AutostartView    `json:"autostart"`
	MCP         mcp.Policy       `json:"mcp"`
	MCPCommand  string           `json:"mcpCommand"`
	Warning     string           `json:"warning,omitempty"`
}

// AutostartView reports the startup entry.
type AutostartView struct {
	Enabled bool   `json:"enabled"`
	Command string `json:"command,omitempty"`
}

// Payload is what Dispatch returns to the frontend.
type Payload struct {
	OK      bool       `json:"ok"`
	Message string     `json:"message,omitempty"`
	State   *StateView `json:"state,omitempty"`
}

// State collects the full UI state under the service lock.
func (a *App) State() (*StateView, error) {
	a.vaultMu.Lock()
	defer a.vaultMu.Unlock()
	return a.stateLocked()
}

func (a *App) stateLocked() (*StateView, error) {
	payload, err := a.store.Load()
	if err != nil {
		return nil, err
	}
	entries, envErr := a.env.List()
	state := &StateView{
		Version:     buildinfo.Version,
		Channel:     buildinfo.Channel,
		Installed:   winsys.IsInstalled(),
		Profiles:    make([]ProfileView, 0, len(payload.Profiles)),
		AppliedKeys: append(make([]string, 0, len(payload.AppliedKeys)), payload.AppliedKeys...),
		System:      systemVariables(entries, payload),
		Settings:    settingsView(settings.Load()),
		Update:      updateView(buildinfo.Version),
		Shell:       a.shell.Status(),
		MCP:         mcp.LoadPolicy(),
		MCPCommand:  mcpCommand(),
	}
	if envErr != nil {
		state.Warning = "无法读取用户环境变量：" + apperr.User(envErr)
	}
	if payload.ActiveProfileID != nil {
		state.ActiveID = *payload.ActiveProfileID
	}
	for _, profile := range payload.Profiles {
		state.Profiles = append(state.Profiles, toProfileView(profile, profile.ID == state.ActiveID))
	}
	sort.Slice(state.Profiles, func(i, j int) bool { return state.Profiles[i].Name < state.Profiles[j].Name })

	switch command, ok, err := winsys.NewUserAutostart().Current(); {
	case err != nil:
		if state.Warning == "" {
			state.Warning = "无法读取开机启动项：" + apperr.User(err)
		}
	case ok:
		state.Autostart = AutostartView{Enabled: true, Command: command}
	}
	return state, nil
}

// StartupMaintenance runs once at launch: it retires a finished update record
// and deletes staged installers. Keeping it out of State() means reads stay free
// of side effects and the error is reported instead of swallowed.
func (a *App) StartupMaintenance() error {
	pending, err := update.ReadPending()
	if err != nil {
		return err
	}
	if pending == nil {
		return nil
	}
	// A record older than the running version means the update already happened
	// (or a newer build was installed by hand); retire it either way.
	order, err := update.CompareVersions(pending.To, buildinfo.Version)
	if err != nil {
		// Keep the record: a malformed version must not delete a verified installer.
		return fmt.Errorf("待安装版本无法解析（%s）：%w", pending.To, err)
	}
	if order > 0 {
		return nil
	}
	// Prune first: if it fails the record stays and the next launch retries.
	if err := update.PruneStaged(pending.Path); err != nil {
		return err
	}
	return update.ClearPending()
}

// AutoCheckIfDue performs the background check promised by the settings page.
// It is silent by design: failures land in update.lastResult and the UI shows
// them the next time the update card is opened.
func (a *App) AutoCheckIfDue() {
	if !winsys.IsInstalled() {
		return
	}
	current := settings.Load()
	if current.Update.Check == settings.CheckOff || !current.Update.DueForCheck(time.Now()) {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	_, _ = update.NewService().Check(ctx)
}

// Dispatch runs one UI action. The frontend sends {action, payload} and gets a
// Payload back; unknown actions are rejected instead of silently ignored.
func (a *App) Dispatch(action string, rawPayload string) (*Payload, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()

	switch action {
	case "window-minimise", "window-toggle-maximise", "window-close":
		// Window chrome lives in the frameless UI now; the host owns the native calls.
		if a.notify != nil {
			a.notify(action)
		}
		return &Payload{OK: true}, nil
	case "apply":
		return a.applyProfile(rawPayload)
	case "deactivate":
		return a.deactivate()
	case "save-profile":
		return a.saveProfile(rawPayload)
	case "delete-profile":
		return a.deleteProfile(rawPayload)
	case "save-settings":
		return a.saveSettings(rawPayload)
	case "set-autostart":
		return a.setAutostart(rawPayload)
	case "shell-install", "shell-uninstall":
		return a.shellAction(action)
	case "set-mcp":
		return a.setMCP(rawPayload)
	case "update-check":
		return a.updateCheck(ctx)
	case "update-download":
		return a.updateDownload(ctx)
	case "update-install":
		return a.updateInstall()
	case "export":
		return a.exportProfiles(rawPayload)
	default:
		return &Payload{OK: false, Message: "未知操作：" + action}, nil
	}
}

func (a *App) respond(message any) (*Payload, error) {
	state, err := a.State()
	if err != nil {
		return &Payload{OK: false, Message: userMessage(err)}, nil
	}
	payload := &Payload{OK: true, State: state}
	if msg, ok := message.(string); ok {
		payload.Message = msg
	}
	return payload, nil
}

// respondLocked is respond for callers that already hold vaultMu.
func (a *App) respondLocked(message any) (*Payload, error) {
	state, err := a.stateLocked()
	if err != nil {
		return &Payload{OK: false, Message: apperr.User(err)}, nil
	}
	payload := &Payload{OK: true, State: state}
	if msg, ok := message.(string); ok {
		payload.Message = msg
	}
	return payload, nil
}

func (a *App) fail(err error) (*Payload, error) {
	return &Payload{OK: false, Message: userMessage(err)}, nil
}

func findProfileByID(payload *model.VaultPayload, id string) *model.EnvProfile {
	for i := range payload.Profiles {
		if payload.Profiles[i].ID == id {
			return &payload.Profiles[i]
		}
	}
	return nil
}

// userMessage drops internal package prefixes before the UI shows them.
func userMessage(err error) string { return apperr.User(err) }

func (a *App) applyProfile(raw string) (*Payload, error) {
	a.vaultMu.Lock()
	defer a.vaultMu.Unlock()
	var request struct {
		ID string `json:"id"`
	}
	if err := decode(raw, &request); err != nil {
		return a.fail(err)
	}
	service := &apply.Service{
		Store:     a.store,
		Env:       a.env,
		Broadcast: winsys.Broadcaster(),
		Shell:     a.shell,
	}
	report, err := service.Activate(request.ID)
	if err != nil {
		return a.fail(err)
	}
	message := fmt.Sprintf("已应用 %s（%d 个变量）；已打开的终端需重新打开才能读到新值", report.Profile, len(report.Applied))
	if len(report.Warnings) > 0 {
		message += "；" + strings.Join(report.Warnings, "；")
	}
	return a.respondLocked(message)
}

func (a *App) deactivate() (*Payload, error) {
	a.vaultMu.Lock()
	defer a.vaultMu.Unlock()
	service := &apply.Service{Store: a.store, Env: a.env, Broadcast: winsys.Broadcaster(), Shell: a.shell}
	report, err := service.Deactivate()
	if err != nil {
		return a.fail(err)
	}
	message := fmt.Sprintf("已移除 %d 个变量", len(report.Stale))
	if len(report.Warnings) > 0 {
		message += "；" + strings.Join(report.Warnings, "；")
	}
	return a.respondLocked(message)
}

func (a *App) saveProfile(raw string) (*Payload, error) {
	a.vaultMu.Lock()
	defer a.vaultMu.Unlock()
	var request struct {
		Profile ProfileView `json:"profile"`
	}
	if err := decode(raw, &request); err != nil {
		return a.fail(err)
	}
	payload, err := a.store.Load()
	if err != nil {
		return a.fail(err)
	}

	profile := model.EnvProfile{
		ID:        request.Profile.ID,
		Name:      request.Profile.Name,
		Note:      request.Profile.Note,
		Tint:      request.Profile.Tint,
		Symbol:    request.Profile.Symbol,
		UpdatedAt: model.Now(),
	}
	if profile.ID == "" {
		profile.ID = newID()
		profile.CreatedAt = model.Now()
	}
	for _, variable := range request.Profile.Variables {
		profile.Variables = append(profile.Variables, model.EnvVariable{
			ID:        choose(variable.ID, newID()),
			Key:       variable.Key,
			Value:     variable.Value,
			IsEnabled: variable.Enabled,
			IsSecret:  variable.Secret,
			Note:      variable.Note,
		})
	}

	// Trim names, notes, variable keys and fill default styling once, so the
	// vault never stores whitespace the UI would then have to render.
	profile = profile.Normalized()

	// The list view masks secret values and the editor posts that object back,
	// so a masked value means "unchanged", not "overwrite the secret with bullets".
	previous := make(map[string]string)
	if existing := findProfileByID(payload, profile.ID); existing != nil {
		for _, variable := range existing.Variables {
			previous[variable.ID] = variable.Value
		}
	}
	for i := range profile.Variables {
		variable := &profile.Variables[i]
		if variable.Value != maskedValue {
			continue
		}
		original, ok := previous[variable.ID]
		if !ok {
			return a.fail(fmt.Errorf("变量 %s 的原值已不可用，请重新输入", variable.Key))
		}
		variable.Value = original
	}

	replaced := false
	for i := range payload.Profiles {
		if payload.Profiles[i].ID == profile.ID {
			profile.CreatedAt = payload.Profiles[i].CreatedAt
			payload.Profiles[i] = profile
			replaced = true
			break
		}
	}
	if !replaced {
		payload.Profiles = append(payload.Profiles, profile)
	}
	if err := a.store.Save(payload); err != nil {
		return a.fail(err)
	}
	return a.respondLocked("配置已保存")
}

func (a *App) deleteProfile(raw string) (*Payload, error) {
	a.vaultMu.Lock()
	defer a.vaultMu.Unlock()
	var request struct {
		ID string `json:"id"`
	}
	if err := decode(raw, &request); err != nil {
		return a.fail(err)
	}
	payload, err := a.store.Load()
	if err != nil {
		return a.fail(err)
	}
	// Deleting the active profile must clean the machine too: leaving the keys
	// behind would keep variables no profile owns, and the UI would still count
	// them as written by EnvBox.
	if payload.ActiveProfileID != nil && *payload.ActiveProfileID == request.ID {
		service := &apply.Service{Store: a.store, Env: a.env, Broadcast: winsys.Broadcaster(), Shell: a.shell}
		if _, err := service.Deactivate(); err != nil {
			return a.fail(err)
		}
		if payload, err = a.store.Load(); err != nil {
			return a.fail(err)
		}
	}
	kept := make([]model.EnvProfile, 0, len(payload.Profiles))
	for _, profile := range payload.Profiles {
		if profile.ID != request.ID {
			kept = append(kept, profile)
		}
	}
	if len(kept) == len(payload.Profiles) {
		return &Payload{OK: false, Message: "找不到要删除的配置"}, nil
	}
	payload.Profiles = kept
	if payload.ActiveProfileID != nil && *payload.ActiveProfileID == request.ID {
		payload.ActiveProfileID = nil
	}
	if err := a.store.Save(payload); err != nil {
		return a.fail(err)
	}
	return a.respondLocked("配置已删除")
}

func (a *App) saveSettings(raw string) (*Payload, error) {
	// Pointer fields distinguish "not provided" from "clear it": a client that
	// only sends {"check":"off"} must not reset unrelated settings.
	var request struct {
		Check          *string `json:"check"`
		SkippedVersion *string `json:"skippedVersion"`
	}
	if err := decode(raw, &request); err != nil {
		return a.fail(err)
	}
	err := settings.Mutate(func(current *settings.Settings) error {
		if request.Check != nil {
			current.Update.Check = settings.NormalizeCheck(*request.Check)
		}
		if request.SkippedVersion != nil {
			current.Update.SkippedVersion = *request.SkippedVersion
		}
		return nil
	})
	if err != nil {
		return a.fail(err)
	}
	return a.respond("设置已保存")
}

func (a *App) setAutostart(raw string) (*Payload, error) {
	var request struct {
		Enabled bool `json:"enabled"`
	}
	if err := decode(raw, &request); err != nil {
		return a.fail(err)
	}
	auto := winsys.NewUserAutostart()
	if !request.Enabled {
		if err := auto.Disable(); err != nil {
			return a.fail(err)
		}
		return a.respond("已关闭开机启动")
	}
	exe, err := winsys.ExecutablePath()
	if err != nil {
		return a.fail(err)
	}
	if err := auto.Enable(exe); err != nil {
		return a.fail(err)
	}
	return a.respond("已开启开机启动")
}

func (a *App) shellAction(action string) (*Payload, error) {
	// Writes active.ps1, which applyProfile also writes; both must hold the lock.
	a.vaultMu.Lock()
	defer a.vaultMu.Unlock()
	if action == "shell-install" {
		if err := a.shell.Install(); err != nil {
			return a.fail(err)
		}
		payload, err := a.store.Load()
		if err != nil {
			return a.fail(err)
		}
		if active := payload.ActiveProfile(); active != nil {
			if err := a.shell.WriteActivation(*active); err != nil {
				return &Payload{OK: false, Message: userMessage(err)}, nil
			}
		}
		return a.respondLocked("已安装 PowerShell 集成")
	}
	if err := a.shell.Uninstall(); err != nil {
		return a.fail(err)
	}
	if err := a.shell.RemoveActivation(); err != nil {
		return a.fail(err)
	}
	return a.respondLocked("已移除 PowerShell 集成")
}

func (a *App) setMCP(raw string) (*Payload, error) {
	var request struct {
		Enabled     bool `json:"enabled"`
		AllowReveal bool `json:"allowReveal"`
	}
	if err := decode(raw, &request); err != nil {
		return a.fail(err)
	}
	if err := mcp.SavePolicy(mcp.Policy{Enabled: request.Enabled, AllowReveal: request.AllowReveal}); err != nil {
		return a.fail(err)
	}
	return a.respond("MCP 设置已更新")
}

func (a *App) updateCheck(ctx context.Context) (*Payload, error) {
	if !winsys.IsInstalled() {
		return &Payload{OK: false, Message: "开发态不参与更新：请使用安装后的 EnvBox"}, nil
	}
	service := update.NewService()
	available, err := service.Check(ctx)
	if err != nil {
		// "已是最新" and "已跳过" are normal answers, not failures.
		if update.IsNoOp(err) {
			return &Payload{OK: true, Message: userMessage(err)}, nil
		}
		return &Payload{OK: false, Message: userMessage(err)}, nil
	}
	state, stateErr := a.State()
	if stateErr != nil {
		return a.fail(stateErr)
	}
	state.Update.Available = available.Version
	state.Update.Notes = available.Notes
	return &Payload{OK: true, Message: "发现新版本 " + available.Version, State: state}, nil
}

func (a *App) updateDownload(ctx context.Context) (*Payload, error) {
	if !winsys.IsInstalled() {
		return &Payload{OK: false, Message: "开发态不参与更新：请使用安装后的 EnvBox"}, nil
	}
	service := update.NewService()
	available, err := service.Check(ctx)
	if err != nil {
		return a.fail(err)
	}
	pending, err := service.Download(ctx, available)
	if err != nil {
		return a.fail(err)
	}
	state, stateErr := a.State()
	if stateErr != nil {
		return a.fail(stateErr)
	}
	state.Update.Pending = pending.To
	state.Update.CanInstall = true
	return &Payload{OK: true, Message: "安装包已下载并校验通过", State: state}, nil
}

func (a *App) updateInstall() (*Payload, error) {
	if !winsys.IsInstalled() {
		return &Payload{OK: false, Message: "开发态不参与更新：请使用安装后的 EnvBox"}, nil
	}
	pending, err := update.ReadPending()
	if err != nil {
		return a.fail(err)
	}
	if pending == nil {
		return &Payload{OK: false, Message: "没有待安装的更新"}, nil
	}
	if err := update.NewService().Install(pending); err != nil {
		return a.fail(err)
	}
	// The installer replaces the running executable, so the window must close.
	go func() {
		time.Sleep(300 * time.Millisecond)
		if a.notify != nil {
			a.notify("quit")
		}
	}()
	return &Payload{OK: true, Message: "安装程序已启动，EnvBox 即将退出"}, nil
}

func (a *App) exportProfiles(raw string) (*Payload, error) {
	a.vaultMu.Lock()
	defer a.vaultMu.Unlock()
	var request struct {
		Passphrase string   `json:"passphrase"`
		IDs        []string `json:"ids"`
	}
	if err := decode(raw, &request); err != nil {
		return a.fail(err)
	}
	payload, err := a.store.Load()
	if err != nil {
		return a.fail(err)
	}
	selected := make([]model.EnvProfile, 0, len(payload.Profiles))
	wanted := make(map[string]struct{}, len(request.IDs))
	for _, id := range request.IDs {
		wanted[id] = struct{}{}
	}
	for _, profile := range payload.Profiles {
		if len(wanted) == 0 {
			selected = append(selected, profile)
			continue
		}
		if _, ok := wanted[profile.ID]; ok {
			selected = append(selected, profile)
		}
	}
	if len(selected) == 0 {
		return &Payload{OK: false, Message: "没有可导出的配置"}, nil
	}
	dir, err := winsys.EnsureConfigDir()
	if err != nil {
		return a.fail(err)
	}
	target, err := portable.ExportToFile(dir, selected, request.Passphrase, 0, model.Now())
	if err != nil {
		return a.fail(err)
	}
	return &Payload{OK: true, Message: "已导出：" + target}, nil
}

func systemVariables(entries []winsys.EnvEntry, payload *model.VaultPayload) []SystemVariable {
	applied := make(map[string]struct{}, len(payload.AppliedKeys))
	for _, key := range payload.AppliedKeys {
		applied[strings.ToUpper(key)] = struct{}{}
	}
	out := make([]SystemVariable, 0, len(entries))
	for _, entry := range entries {
		if entry.Value == "" && entry.Expanded == "" {
			continue
		}
		_, isApplied := applied[strings.ToUpper(entry.Name)]
		out = append(out, SystemVariable{
			Key:       entry.Name,
			Value:     entry.Expanded,
			Kind:      kindOf(entry.Type),
			Sensitive: isSensitive(entry.Name),
			Applied:   isApplied,
		})
	}
	return out
}

func kindOf(valueType uint32) string {
	switch valueType {
	case winsys.RegExpandSZ:
		return "expand"
	case winsys.RegSZ:
		return "string"
	default:
		return "other"
	}
}

func isSensitive(key string) bool {
	upper := strings.ToUpper(key)
	for _, marker := range []string{"PASSWORD", "SECRET", "TOKEN", "APIKEY", "API_KEY", "PRIVATE", "CREDENTIAL", "AUTH"} {
		if strings.Contains(upper, marker) {
			return true
		}
	}
	return false
}

func toProfileView(profile model.EnvProfile, active bool) ProfileView {
	view := ProfileView{
		ID: profile.ID, Name: profile.Name, Note: profile.Note,
		Tint: profile.Tint, Symbol: profile.Symbol, Active: active,
		UpdatedAt: profile.UpdatedAt.ISO8601(),
		Secrets:   profile.SecretCount(), Variables: make([]VarView, 0, len(profile.Variables)),
	}
	for _, variable := range profile.Variables {
		if variable.IsEnabled {
			view.Enabled++
		}
		value := variable.Value
		masked := false
		if variable.IsSecret && value != "" {
			value = maskedValue
			masked = true
		}
		view.Variables = append(view.Variables, VarView{
			ID: variable.ID, Key: variable.Key, Value: value, Masked: masked,
			Enabled: variable.IsEnabled, Secret: variable.IsSecret, Note: variable.Note,
		})
	}
	return view
}

func settingsView(current settings.Settings) SettingsView {
	return SettingsView{
		Check:          string(current.Update.Check),
		SkippedVersion: current.Update.SkippedVersion,
		LastCheckAt:    current.Update.LastCheckAt,
		LastResult:     current.Update.LastResult,
	}
}

func updateView(current string) UpdateView {
	view := UpdateView{
		Current: current,
		Signing: buildinfo.SigningConfigured(),
		HTMLURL: "https://github.com/" + buildinfo.UpdateRepo + "/releases/latest",
	}
	pending, err := update.ReadPending()
	switch {
	case err != nil:
		view.PendingError = apperr.User(err)
	case pending != nil:
		view.Pending = pending.To
		view.CanInstall = true
	}
	return view
}

// mcpCommand is the command line MCP clients should spawn.
func mcpCommand() string {
	exe, err := winsys.ExecutablePath()
	if err != nil {
		return "envbox.exe mcp"
	}
	return filepath.Join(filepath.Dir(exe), "bin", "envbox.exe") + " mcp"
}

func decode(raw string, target any) error {
	if strings.TrimSpace(raw) == "" {
		return errors.New("缺少参数")
	}
	if err := json.Unmarshal([]byte(raw), target); err != nil {
		return fmt.Errorf("参数格式错误：%w", err)
	}
	return nil
}

func choose(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

func newID() string {
	id, err := vault.NewKeyID()
	if err != nil {
		return fmt.Sprintf("id-%d", time.Now().UnixNano())
	}
	return id
}
