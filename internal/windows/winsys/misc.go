//go:build windows

package winsys

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"

	"github.com/Ohhu/EnvBox/internal/core/buildinfo"
)

// BroadcastSettingChange posts WM_SETTINGCHANGE without waiting for any window to
// process it. SendMessageTimeoutW walks every top-level window, and one
// unresponsive app can stall activation for minutes; the notification needs no
// reply, so the non-blocking variant is the correct one everywhere.
func BroadcastSettingChange() error {
	env, err := syscall.UTF16PtrFromString("Environment")
	if err != nil {
		return err
	}
	const (
		hwndBroadcast = 0xffff
		wmSettingChg  = 0x001A
	)
	procSendNotifyMessage := user32.NewProc("SendNotifyMessageW")
	ret, _, _ := procSendNotifyMessage.Call(
		hwndBroadcast, wmSettingChg, 0, uintptr(unsafe.Pointer(env)),
	)
	if ret == 0 {
		// LazyProc.Call's error is always non-nil (it reports "operation completed
		// successfully" on success), so the raw value is useless to users.
		return errors.New("winsys: 发送失败")
	}
	return nil
}

// skipBroadcastEnv lets end-to-end tests skip the WM_SETTINGCHANGE broadcast so
// activation stays deterministic on a busy desktop. It only takes effect outside
// production builds.
const skipBroadcastEnv = "ENVBOX_SKIP_BROADCAST"

// Broadcaster returns the function activation should use.
func Broadcaster() func() error {
	if os.Getenv(skipBroadcastEnv) != "" && buildinfo.Channel != "production" {
		return func() error { return nil }
	}
	return BroadcastSettingChange
}

// RunKeyPath is where Windows looks for per-user startup programs.
const RunKeyPath = `Software\Microsoft\Windows\CurrentVersion\Run`

// RunValueName is the value EnvBox owns inside the Run key.
const RunValueName = "EnvBox"

// Autostart manages the per-user startup entry.
type Autostart struct {
	// KeyPath defaults to RunKeyPath; tests point it at a sandbox key.
	KeyPath string
}

// NewUserAutostart targets the real Run key.
func NewUserAutostart() *Autostart { return &Autostart{KeyPath: RunKeyPath} }

func (a *Autostart) path() string {
	if a.KeyPath == "" {
		return RunKeyPath
	}
	return a.KeyPath
}

// Enable registers exePath to start at login.
func (a *Autostart) Enable(exePath string) error {
	key, err := CreateUserKey(a.path())
	if err != nil {
		return err
	}
	defer key.Close()
	return key.SetString(RunValueName, quoteCommand(exePath), RegSZ)
}

// Disable removes the startup entry.
func (a *Autostart) Disable() error {
	key, err := OpenUserKey(a.path())
	if err != nil {
		if errors.Is(err, ErrorFileNotFound) {
			return nil
		}
		return err
	}
	defer key.Close()
	return key.DeleteValue(RunValueName)
}

// Current returns the registered command, if any.
func (a *Autostart) Current() (string, bool, error) {
	key, err := OpenUserKey(a.path())
	if err != nil {
		if errors.Is(err, ErrorFileNotFound) {
			return "", false, nil
		}
		return "", false, err
	}
	defer key.Close()
	_, value, err := key.QueryString(RunValueName)
	if err != nil {
		if errors.Is(err, ErrorFileNotFound) {
			return "", false, nil
		}
		return "", false, err
	}
	return value, value != "", nil
}

// quoteCommand wraps a path in double quotes: the Run key only treats double
// quotes as delimiters, so a path with spaces fails without them.
func quoteCommand(path string) string {
	if strings.HasPrefix(path, "\"") {
		return path
	}
	return "\"" + path + "\""
}

// LocalAppDataDir returns %LOCALAPPDATA%\EnvBox without touching the filesystem.
// Read paths must not create directories: a missing folder means "no vault yet",
// and a read-only context must still be able to report that instead of failing.
func LocalAppDataDir() (string, error) {
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		return "", fmt.Errorf("winsys: 找不到 LOCALAPPDATA")
	}
	return filepath.Join(base, "EnvBox"), nil
}

// ConfigDirEnv lets development builds relocate the config directory (vault,
// policy, settings) so tests and CI can run end-to-end without touching the real
// user profile. Production builds ignore it: an attacker who can set environment
// variables could otherwise redirect the vault path.
const ConfigDirEnv = "ENVBOX_CONFIG_DIR"

// ConfigDir returns the directory holding the vault, policy and settings.
func ConfigDir() (string, error) {
	if override := os.Getenv(ConfigDirEnv); override != "" && buildinfo.Channel != "production" {
		return override, nil
	}
	return LocalAppDataDir()
}

// EnsureConfigDir creates the config directory for write paths.
func EnsureConfigDir() (string, error) {
	dir, err := ConfigDir()
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	return dir, nil
}

// ExecutablePath returns the absolute path of the running executable.
func ExecutablePath() (string, error) { return os.Executable() }

// InstallDir is where the installer puts the app.
func InstallDir() string {
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		return ""
	}
	return filepath.Join(base, "Programs", "EnvBox")
}

// IsInstalled reports whether the running executable lives in the install dir.
// Development builds (go run, wails3 dev) are not considered installed, which is
// what disables the updater and the registry-writing toggles.
func IsInstalled() bool {
	exe, err := os.Executable()
	if err != nil {
		return false
	}
	install := InstallDir()
	if install == "" {
		return false
	}
	exeDir := strings.ToLower(filepath.Dir(exe))
	return exeDir == strings.ToLower(install) || strings.HasPrefix(exeDir, strings.ToLower(install)+strings.ToLower(string(os.PathSeparator)))
}

// MutexName is the single-instance name. The installer looks it up to decide
// whether EnvBox is running; it never blocks on it, because QuitEventName is
// what actually closes the app.
const MutexName = "EnvBox-SingleInstance-5C1F7C2E"

// AcquireSingleInstance creates the named mutex. alreadyRunning is true when
// another instance owns it; release must be called on exit.
func AcquireSingleInstance() (release func(), alreadyRunning bool, err error) {
	name, err := syscall.UTF16PtrFromString(MutexName)
	if err != nil {
		return nil, false, err
	}
	handle, _, callErr := procCreateMutex.Call(0, 0, uintptr(unsafe.Pointer(name)))
	if handle == 0 {
		// Access denied usually means a release build is already running at a
		// higher integrity level; anything else points at a security product.
		return nil, false, fmt.Errorf("winsys: 无法启动 EnvBox：系统拒绝创建程序锁（%v），请确认没有安全软件拦截，详见 startup.log", callErr)
	}
	release = func() { procCloseHandle.Call(handle) }
	if errno, ok := callErr.(syscall.Errno); ok && errno == syscall.ERROR_ALREADY_EXISTS {
		return release, true, nil
	}
	return release, false, nil
}

// QuitEventName is the named event a running instance waits on. The installer
// sets it before replacing files, so an upgrade closes the tray app instead of
// asking the user to do it by hand. `EnvBox.exe --quit` sets it as well.
const QuitEventName = "EnvBox-Quit-5C1F7C2E"

const (
	eventModifyState = 0x0002
	infiniteWait     = 0xFFFFFFFF
)

// ListenForQuit creates the quit event and returns a channel that closes when
// another process asks this instance to exit. stop releases the handle.
func ListenForQuit() (quit <-chan struct{}, stop func(), err error) {
	name, err := syscall.UTF16PtrFromString(QuitEventName)
	if err != nil {
		return nil, nil, err
	}
	// Manual reset: the signal must stay set until this process exits, even if
	// the installer sets it again while the window is still closing.
	handle, _, callErr := procCreateEvent.Call(0, 1, 0, uintptr(unsafe.Pointer(name)))
	if handle == 0 {
		return nil, nil, fmt.Errorf("winsys: 无法创建退出信号：%w", callErr)
	}
	signal := make(chan struct{})
	go func() {
		procWaitForSingleObject.Call(handle, infiniteWait)
		close(signal)
	}()
	return signal, func() { procCloseHandle.Call(handle) }, nil
}

// RequestQuit asks a running instance to exit. It reports whether one was
// listening: false means no instance is running, or it predates the quit event.
func RequestQuit() bool {
	name, err := syscall.UTF16PtrFromString(QuitEventName)
	if err != nil {
		return false
	}
	handle, _, _ := procOpenEvent.Call(eventModifyState, 0, uintptr(unsafe.Pointer(name)))
	if handle == 0 {
		return false
	}
	defer procCloseHandle.Call(handle)
	ok, _, _ := procSetEvent.Call(handle)
	return ok != 0
}

// ShowError reports a fatal startup problem. The GUI is built with
// -H windowsgui, so stderr goes nowhere and a message box is the only channel.
func ShowError(title, message string) {
	procMessageBox := user32.NewProc("MessageBoxW")
	text, err := syscall.UTF16PtrFromString(title)
	if err != nil {
		return
	}
	body, err := syscall.UTF16PtrFromString(message)
	if err != nil {
		return
	}
	procMessageBox.Call(0, uintptr(unsafe.Pointer(body)), uintptr(unsafe.Pointer(text)), 0x00000010|0x00000000)
}
