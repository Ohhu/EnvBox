//go:build windows

// Package winsys wraps the Windows APIs EnvBox needs. Everything here is plain
// syscall/LazyDLL: no cgo, no third-party modules, so the whole build stays
// auditable and cross-compilable with CGO_ENABLED=0.
package winsys

import (
	"errors"
	"syscall"
	"unsafe"
)

// Registry value types EnvBox reads and writes.
const (
	RegSZ       = 1
	RegExpandSZ = 2
)

// Access rights.
const (
	KeyQueryValue       = 0x0001
	KeySetValue         = 0x0002
	KeyCreateSubKey     = 0x0004
	KeyEnumerateSubKeys = 0x0008
	KeyNotify           = 0x0010
	KeyRead             = KeyQueryValue | KeyEnumerateSubKeys | KeyNotify
	KeyWrite            = KeySetValue | KeyCreateSubKey
	KeyReadWrite        = KeyRead | KeyWrite
	KeyAllAccess        = 0x000F003F
)

// Win32 error codes we branch on.
const (
	ErrorFileNotFound = syscall.Errno(2)
	ErrorAccessDenied = syscall.Errno(5)
	ErrorNoMoreItems  = syscall.Errno(259)
)

var (
	advapi32 = syscall.NewLazyDLL("advapi32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	user32   = syscall.NewLazyDLL("user32.dll")

	procRegOpenKeyEx    = advapi32.NewProc("RegOpenKeyExW")
	procRegCreateKeyEx  = advapi32.NewProc("RegCreateKeyExW")
	procRegCloseKey     = advapi32.NewProc("RegCloseKey")
	procRegQueryValueEx = advapi32.NewProc("RegQueryValueExW")
	procRegEnumValue    = advapi32.NewProc("RegEnumValueW")
	procRegSetValueEx   = advapi32.NewProc("RegSetValueExW")
	procRegDeleteValue  = advapi32.NewProc("RegDeleteValueW")
	procRegDeleteKeyEx  = advapi32.NewProc("RegDeleteKeyExW")

	procExpandEnvironmentStrings = kernel32.NewProc("ExpandEnvironmentStringsW")
	procCreateMutex              = kernel32.NewProc("CreateMutexW")
	procCloseHandle              = kernel32.NewProc("CloseHandle")
	procCreateEvent              = kernel32.NewProc("CreateEventW")
	procOpenEvent                = kernel32.NewProc("OpenEventW")
	procSetEvent                 = kernel32.NewProc("SetEvent")
	procWaitForSingleObject      = kernel32.NewProc("WaitForSingleObject")

	procCryptProtectData   = crypt32().NewProc("CryptProtectData")
	procCryptUnprotectData = crypt32().NewProc("CryptUnprotectData")
	procLocalFree          = kernel32.NewProc("LocalFree")
)

func crypt32() *syscall.LazyDLL { return syscall.NewLazyDLL("crypt32.dll") }

// registryError carries a Chinese message for users while keeping the Win32
// errno available for errors.Is checks.
type registryError struct {
	op     string
	path   string
	status uint32
	errno  error
}

func (e *registryError) Error() string {
	return "winsys: " + e.op + " " + e.path + " 失败（" + statusHint(e.status) + "）"
}

func (e *registryError) Unwrap() error { return e.errno }

// statusHint maps the LSTATUS values EnvBox can hit to plain text.
func statusHint(status uint32) string {
	switch status {
	case 2:
		return "对象不存在"
	case 5:
		return "权限不足"
	case 87:
		return "参数无效"
	case 1011:
		return "键已被标记为删除"
	case 1018:
		return "键已被删除"
	default:
		return "注册表错误"
	}
}

// Key is an open registry key.
type Key struct {
	handle syscall.Handle
	path   string
}

// valuePathForError names both the key and the value so the message is locatable.
func (k *Key) valuePathForError(name string) string {
	return k.pathForError() + "\\" + name
}

// pathForError labels errors from key-scoped calls; the handle alone is not
// meaningful to a reader.
func (k *Key) pathForError() string {
	if k.path == "" {
		return "HKCU"
	}
	return k.path
}

// Close releases the key handle.
func (k *Key) Close() error {
	if k == nil || k.handle == 0 {
		return nil
	}
	procRegCloseKey.Call(uintptr(k.handle))
	k.handle = 0
	return nil
}

func openKey(root syscall.Handle, path string, access uint32) (*Key, error) {
	name, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return nil, err
	}
	var handle syscall.Handle
	lstatus, _, _ := procRegOpenKeyEx.Call(
		uintptr(root), uintptr(unsafe.Pointer(name)), 0, uintptr(access),
		uintptr(unsafe.Pointer(&handle)),
	)
	if lstatus != 0 {
		return nil, &registryError{op: "打开注册表", path: path, status: uint32(lstatus), errno: syscall.Errno(lstatus)}
	}
	return &Key{handle: handle, path: path}, nil
}

// OpenUserKey opens a key under HKEY_CURRENT_USER with read/write access.
func OpenUserKey(path string) (*Key, error) {
	return openKey(syscall.HKEY_CURRENT_USER, path, KeyReadWrite)
}

// CreateUserKey opens or creates a key under HKEY_CURRENT_USER.
func CreateUserKey(path string) (*Key, error) {
	name, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return nil, err
	}
	var handle syscall.Handle
	var disposition uint32
	lstatus, _, _ := procRegCreateKeyEx.Call(
		uintptr(syscall.HKEY_CURRENT_USER), uintptr(unsafe.Pointer(name)), 0, 0, 0,
		KeyAllAccess, 0, uintptr(unsafe.Pointer(&handle)), uintptr(unsafe.Pointer(&disposition)),
	)
	if lstatus != 0 {
		return nil, &registryError{op: "创建注册表键", path: path, status: uint32(lstatus), errno: syscall.Errno(lstatus)}
	}
	return &Key{handle: handle, path: path}, nil
}

// Value is a raw registry value.
type Value struct {
	Name string
	Type uint32
	Data []byte
}

// Values enumerates every value of the key.
func (k *Key) Values() ([]Value, error) {
	var out []Value
	nameBuf := make([]uint16, 512)
	for index := uint32(0); ; index++ {
		nameLen := uint32(len(nameBuf))
		var valueType uint32
		dataLen := uint32(0)

		// First call gets the size, second gets the data. Asking for both in one
		// call is not possible without knowing the size up front.
		lstatus, _, _ := procRegEnumValue.Call(
			uintptr(k.handle), uintptr(index),
			uintptr(unsafe.Pointer(&nameBuf[0])), uintptr(unsafe.Pointer(&nameLen)),
			0, uintptr(unsafe.Pointer(&valueType)), 0, uintptr(unsafe.Pointer(&dataLen)),
		)
		status := syscall.Errno(lstatus)
		switch {
		case status == ErrorNoMoreItems:
			return out, nil
		case status == syscall.ERROR_MORE_DATA:
			// value has data; fall through to fetch it
		case status != 0:
			return nil, &registryError{op: "枚举注册表值", path: k.pathForError(), status: uint32(lstatus), errno: status}
		}

		data := make([]byte, dataLen)
		var dataPtr uintptr
		if dataLen > 0 {
			dataPtr = uintptr(unsafe.Pointer(&data[0]))
		}
		nameLen = uint32(len(nameBuf))
		lstatus, _, _ = procRegEnumValue.Call(
			uintptr(k.handle), uintptr(index),
			uintptr(unsafe.Pointer(&nameBuf[0])), uintptr(unsafe.Pointer(&nameLen)),
			0, uintptr(unsafe.Pointer(&valueType)), dataPtr, uintptr(unsafe.Pointer(&dataLen)),
		)
		if status = syscall.Errno(lstatus); status != 0 {
			return nil, &registryError{op: "读取注册表值", path: k.pathForError(), status: uint32(lstatus), errno: status}
		}
		out = append(out, Value{
			Name: syscall.UTF16ToString(nameBuf[:nameLen]),
			Type: valueType,
			Data: data[:dataLen],
		})
	}
}

// QueryString reads a REG_SZ / REG_EXPAND_SZ value without expanding it.
func (k *Key) QueryString(name string) (uint32, string, error) {
	namePtr, err := syscall.UTF16PtrFromString(name)
	if err != nil {
		return 0, "", err
	}
	buf := make([]uint16, 32*1024)
	size := uint32(len(buf) * 2)
	var valueType uint32
	lstatus, _, _ := procRegQueryValueEx.Call(
		uintptr(k.handle), uintptr(unsafe.Pointer(namePtr)), 0,
		uintptr(unsafe.Pointer(&valueType)),
		uintptr(unsafe.Pointer(&buf[0])), uintptr(unsafe.Pointer(&size)),
	)
	if status := syscall.Errno(lstatus); status != 0 {
		return 0, "", &registryError{op: "读取注册表值", path: k.valuePathForError(name), status: uint32(lstatus), errno: status}
	}
	chars := size / 2
	for chars > 0 && buf[chars-1] == 0 {
		chars--
	}
	return valueType, syscall.UTF16ToString(buf[:chars]), nil
}

// SetString writes a string value with an explicit registry type.
// Preserving REG_EXPAND_SZ matters: writing REG_SZ would freeze %USERPROFILE%
// expansions into absolute paths.
func (k *Key) SetString(name, value string, valueType uint32) error {
	namePtr, err := syscall.UTF16PtrFromString(name)
	if err != nil {
		return err
	}
	data, err := syscall.UTF16FromString(value)
	if err != nil {
		return err
	}
	lstatus, _, _ := procRegSetValueEx.Call(
		uintptr(k.handle), uintptr(unsafe.Pointer(namePtr)), 0, uintptr(valueType),
		uintptr(unsafe.Pointer(&data[0])), uintptr(len(data)*2),
	)
	if lstatus != 0 {
		return &registryError{op: "写入注册表值", path: k.valuePathForError(name), status: uint32(lstatus), errno: syscall.Errno(lstatus)}
	}
	return nil
}

// DeleteValue removes a value; a missing value is not an error.
func (k *Key) DeleteValue(name string) error {
	namePtr, err := syscall.UTF16PtrFromString(name)
	if err != nil {
		return err
	}
	lstatus, _, _ := procRegDeleteValue.Call(uintptr(k.handle), uintptr(unsafe.Pointer(namePtr)))
	if status := syscall.Errno(lstatus); status != 0 && status != ErrorFileNotFound {
		return &registryError{op: "删除注册表值", path: k.valuePathForError(name), status: uint32(lstatus), errno: status}
	}
	return nil
}

// ExpandEnvironment expands %VAR% references using the current process environment.
func ExpandEnvironment(value string) string {
	if value == "" {
		return ""
	}
	src, err := syscall.UTF16PtrFromString(value)
	if err != nil {
		return value
	}
	buf := make([]uint16, 32*1024)
	written, _, _ := procExpandEnvironmentStrings.Call(
		uintptr(unsafe.Pointer(src)), uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)),
	)
	if written == 0 || written > uintptr(len(buf)) {
		return value
	}
	chars := int(written) - 1
	if chars < 0 {
		chars = 0
	}
	return syscall.UTF16ToString(buf[:chars])
}

// IsAccessDenied reports whether err is a Windows access-denied failure.
// The DSH sandbox denies registry writes, so callers use this to skip cleanly.
func IsAccessDenied(err error) bool {
	return errors.Is(err, ErrorAccessDenied)
}
