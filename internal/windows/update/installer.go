//go:build windows

package update

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/Ohhu/EnvBox/internal/windows/fsx"
	"github.com/Ohhu/EnvBox/internal/windows/winsys"
)

// PendingFileName records an update that has been downloaded and verified but
// not yet confirmed as installed.
const PendingFileName = "update-pending.json"

// Pending is the on-disk handoff between "downloaded" and "installed".
type Pending struct {
	From   string `json:"from"`
	To     string `json:"to"`
	SHA256 string `json:"sha256"`
	Path   string `json:"path"`
	At     string `json:"at"`
}

// UpdatesDir is where installers are staged: <config>/updates/<version>/.
func UpdatesDir() (string, error) {
	dir, err := winsys.ConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "updates"), nil
}

// PendingPath is the update-pending.json location.
func PendingPath() (string, error) {
	dir, err := winsys.ConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, PendingFileName), nil
}

// ReadPending returns the pending record, or nil when there is none.
func ReadPending() (*Pending, error) {
	filePath, err := PendingPath()
	if err != nil {
		return nil, err
	}
	raw, err := os.ReadFile(filePath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}
	var pending Pending
	if err := json.Unmarshal(raw, &pending); err != nil {
		return nil, errors.New("update: 待安装记录已损坏，请重新下载更新")
	}
	return &pending, nil
}

// WritePending persists the handoff record.
func WritePending(pending Pending) error {
	filePath, err := PendingPath()
	if err != nil {
		return err
	}
	if _, err := winsys.EnsureConfigDir(); err != nil {
		return err
	}
	encoded, err := json.MarshalIndent(pending, "", "  ")
	if err != nil {
		return err
	}
	return fsx.WriteFileAtomic(filePath, encoded, 0o600)
}

// ClearPending removes the handoff record.
func ClearPending() error {
	filePath, err := PendingPath()
	if err != nil {
		return err
	}
	if err := os.Remove(filePath); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

// PruneStaged removes the staged installer tree that the given file lives in,
// so consecutive updates do not accumulate installers.
func PruneStaged(stagedPath string) error {
	if stagedPath == "" {
		return nil
	}
	root, err := UpdatesDir()
	if err != nil {
		return err
	}
	dir := filepath.Dir(stagedPath)
	rel, err := filepath.Rel(root, dir)
	if err != nil || rel == "." || strings.HasPrefix(rel, "..") {
		return nil
	}
	return os.RemoveAll(dir)
}

// describeFileError classifies a file error instead of echoing the OS text.
func describeFileError(err error) string {
	switch {
	case errors.Is(err, os.ErrNotExist):
		return "找不到安装包，请重新下载"
	case errors.Is(err, os.ErrPermission):
		return "没有权限执行安装包"
	default:
		return "无法启动安装包"
	}
}

// SilentArgs installs without a wizard and without a reboot.
//
// The per-user installer needs no elevation, so this never triggers UAC.
func SilentArgs() []string {
	return []string{"/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/CLOSEAPPLICATIONS", "/SP-"}
}

// LaunchInstaller starts the installer and returns immediately: the caller is
// expected to exit so the executable can be replaced.
func LaunchInstaller(path string) error {
	if _, err := os.Stat(path); err != nil {
		return fmt.Errorf("update: %s", describeFileError(err))
	}
	cmd := exec.Command(path, SilentArgs()...)
	cmd.Dir = filepath.Dir(path)
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("update: %s", describeFileError(err))
	}
	return nil
}
