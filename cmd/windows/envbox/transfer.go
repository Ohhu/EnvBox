//go:build windows

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/Ohhu/EnvBox/internal/core/model"
	"github.com/Ohhu/EnvBox/internal/core/portable"
)

// importPendingTTL bounds how long a chosen file stays armed for the password
// step, so an abandoned pick cannot be imported by a later click.
const importPendingTTL = 10 * time.Minute

// ImportPick describes the file the native dialog returned. Only the name and
// size travel to the UI: the path stays in the host, and the import action reads
// the file the user picked instead of accepting a path from the page.
type ImportPick struct {
	Name  string `json:"name"`
	Bytes int64  `json:"bytes"`
}

// duplicateProfile copies a profile with fresh ids and a free name, the same
// action as "复制配置" in the macOS build.
func (a *App) duplicateProfile(raw string) (*Payload, error) {
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
	source := findProfileByID(payload, request.ID)
	if source == nil {
		return &Payload{OK: false, Message: "找不到要复制的配置"}, nil
	}
	if len(payload.Profiles) >= model.MaxProfiles {
		return &Payload{OK: false, Message: fmt.Sprintf("配置数量已达上限 %d 个", model.MaxProfiles)}, nil
	}

	duplicate := *source
	duplicate.ID = newID()
	duplicate.Name = uniqueProfileName(source.Name+" 副本", payload.Profiles)
	duplicate.CreatedAt = model.Now()
	duplicate.UpdatedAt = duplicate.CreatedAt
	duplicate.Variables = make([]model.EnvVariable, 0, len(source.Variables))
	for _, variable := range source.Variables {
		clone := variable
		clone.ID = newID()
		duplicate.Variables = append(duplicate.Variables, clone)
	}
	payload.Profiles = append(payload.Profiles, duplicate)
	if err := a.store.Save(payload); err != nil {
		return a.fail(err)
	}

	result, err := a.respondLocked("已复制配置：" + duplicate.Name)
	if err != nil {
		return nil, err
	}
	result.Focus = duplicate.ID
	return result, nil
}

// pickImport asks the host for a file and remembers it. The UI calls this first,
// shows the name and size with the password field, and only then imports.
func (a *App) pickImport() (*Payload, error) {
	if a.dialog == nil {
		return &Payload{
			OK:      false,
			Message: "当前版本无法打开文件选择框；可改用命令行：envbox import <文件> --password <密码>",
		}, nil
	}
	path, err := a.dialog()
	if err != nil {
		return a.fail(err)
	}
	if path == "" {
		// Cancelled: not an error, and no password sheet should open.
		return &Payload{OK: true}, nil
	}
	info, err := os.Stat(path)
	if err != nil {
		return a.fail(err)
	}
	if info.Size() > model.MaxVaultFileBytes {
		return &Payload{OK: false, Message: "文件超过 20 MB 上限，不是 EnvBox 导出文件"}, nil
	}

	a.pickMu.Lock()
	a.pendingImport = path
	a.pendingImportAt = time.Now()
	a.pickMu.Unlock()

	return &Payload{OK: true, Pick: &ImportPick{Name: filepath.Base(path), Bytes: info.Size()}}, nil
}

// importArchive decrypts the picked archive and appends its profiles. Name and
// id clashes are resolved the way the macOS build does it: rename, re-key, keep
// both — an import must never overwrite what is already here.
func (a *App) importArchive(raw string) (*Payload, error) {
	a.vaultMu.Lock()
	defer a.vaultMu.Unlock()
	var request struct {
		Passphrase string `json:"passphrase"`
	}
	if err := decode(raw, &request); err != nil {
		return a.fail(err)
	}

	a.pickMu.Lock()
	path, pickedAt := a.pendingImport, a.pendingImportAt
	a.pendingImport, a.pendingImportAt = "", time.Time{}
	a.pickMu.Unlock()
	if path == "" {
		return &Payload{OK: false, Message: "请先选择要导入的 .envbox 文件"}, nil
	}
	if time.Since(pickedAt) > importPendingTTL {
		return &Payload{OK: false, Message: "选择的文件已过期，请重新选择"}, nil
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return a.fail(err)
	}
	archive, err := portable.Import(data, request.Passphrase)
	if err != nil {
		return a.fail(err)
	}

	payload, err := a.store.Load()
	if err != nil {
		return a.fail(err)
	}
	if len(payload.Profiles)+len(archive.Profiles) > model.MaxProfiles {
		return &Payload{
			OK:      false,
			Message: fmt.Sprintf("导入后会有 %d 个配置，超过 %d 个上限", len(payload.Profiles)+len(archive.Profiles), model.MaxProfiles),
		}, nil
	}

	usedIDs := make(map[string]struct{}, len(payload.Profiles)+len(archive.Profiles))
	for _, profile := range payload.Profiles {
		usedIDs[profile.ID] = struct{}{}
	}
	working := payload.Profiles
	imported := make([]model.EnvProfile, 0, len(archive.Profiles))
	renamed := false
	now := model.Now()
	for _, original := range archive.Profiles {
		profile := original.Normalized()
		if _, clash := usedIDs[profile.ID]; clash {
			profile.ID = newID()
		}
		usedIDs[profile.ID] = struct{}{}
		if name := uniqueProfileName(profile.Name, working); name != profile.Name {
			profile.Name = name
			renamed = true
		}
		profile.CreatedAt = now
		profile.UpdatedAt = now
		for i := range profile.Variables {
			profile.Variables[i].ID = newID()
		}
		working = append(working, profile)
		imported = append(imported, profile)
	}

	payload.Profiles = append(payload.Profiles, imported...)
	if err := a.store.Save(payload); err != nil {
		return a.fail(err)
	}

	message := fmt.Sprintf("已导入 %d 个配置", len(imported))
	if renamed {
		message += "（重名的已自动改名）"
	}
	result, err := a.respondLocked(message)
	if err != nil {
		return nil, err
	}
	if len(imported) > 0 {
		result.Focus = imported[0].ID
	}
	return result, nil
}

// uniqueProfileName mirrors EnvBoxValidation.uniqueProfileName on macOS: keep the
// proposed name, and when it is taken append " 2", " 3"… Comparison is
// case-insensitive because that is how the model checks for duplicates.
func uniqueProfileName(proposed string, existing []model.EnvProfile) string {
	base := strings.TrimSpace(proposed)
	if base == "" {
		base = "未命名配置"
	}
	base = truncateName(base)
	taken := make(map[string]struct{}, len(existing)+1)
	for _, profile := range existing {
		taken[strings.ToLower(profile.Normalized().Name)] = struct{}{}
	}
	if _, clash := taken[strings.ToLower(base)]; !clash {
		return base
	}
	for index := 2; ; index++ {
		suffix := " " + strconv.Itoa(index)
		prefix := truncateName(base)
		if runes := []rune(prefix); len(runes)+len([]rune(suffix)) > model.MaxProfileNameLength {
			prefix = string(runes[:model.MaxProfileNameLength-len([]rune(suffix))])
		}
		candidate := prefix + suffix
		if _, clash := taken[strings.ToLower(candidate)]; !clash {
			return candidate
		}
	}
}

func truncateName(name string) string {
	runes := []rune(name)
	if len(runes) <= model.MaxProfileNameLength {
		return name
	}
	return string(runes[:model.MaxProfileNameLength])
}
