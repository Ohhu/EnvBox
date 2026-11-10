//go:build windows

package winsys

import (
	"errors"
	"fmt"
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"
)

// Clipboard support. macOS marks secret copies as concealed and clears them
// after a delay; Windows has the same idea spelled with clipboard formats that
// clipboard history, cloud sync and text suggestions are documented to honour.

const (
	cfUnicodeText = 13
	gmemMoveable  = 0x0002
)

var (
	procOpenClipboard     = user32.NewProc("OpenClipboard")
	procCloseClipboard    = user32.NewProc("CloseClipboard")
	procEmptyClipboard    = user32.NewProc("EmptyClipboard")
	procGetClipboardData  = user32.NewProc("GetClipboardData")
	procSetClipboardData  = user32.NewProc("SetClipboardData")
	procIsClipboardFormat = user32.NewProc("IsClipboardFormatAvailable")
	procRegisterFormat    = user32.NewProc("RegisterClipboardFormatW")
	procGlobalAlloc       = kernel32.NewProc("GlobalAlloc")
	procGlobalFree        = kernel32.NewProc("GlobalFree")
	procGlobalLock        = kernel32.NewProc("GlobalLock")
	procGlobalUnlock      = kernel32.NewProc("GlobalUnlock")
	procGlobalSize        = kernel32.NewProc("GlobalSize")
	procRtlMoveMemory     = kernel32.NewProc("RtlMoveMemory")
)

// sensitiveFormats alias macOS' org.nspasteboard.ConcealedType: a payload that
// carries them is skipped by clipboard history, cloud clipboard and the Windows
// 11 text monitor.
var sensitiveFormats = []string{
	"ExcludeClipboardContentFromMonitorProcessing",
	"CanIncludeInClipboardHistory",
	"CanUploadToCloudClipboard",
}

// CopyText replaces the clipboard with text. sensitive also keeps it out of
// clipboard history and cloud sync.
func CopyText(text string, sensitive bool) error {
	return withClipboard(func() error {
		if ok, _, callErr := procEmptyClipboard.Call(); ok == 0 {
			return fmt.Errorf("winsys: 无法清空剪贴板（%v）", callErr)
		}
		if err := setClipboardText(text); err != nil {
			return err
		}
		if sensitive {
			for _, name := range sensitiveFormats {
				setClipboardFlag(name)
			}
		}
		return nil
	})
}

// ClipboardText reports the current clipboard text. ok is false when the
// clipboard holds something else, which is the normal case.
func ClipboardText() (text string, ok bool) {
	err := withClipboard(func() error {
		if present, _, _ := procIsClipboardFormat.Call(cfUnicodeText); present == 0 {
			return nil
		}
		handle, _, _ := procGetClipboardData.Call(cfUnicodeText)
		if handle == 0 {
			return nil
		}
		size, _, _ := procGlobalSize.Call(handle)
		if size < 2 || size > 4<<20 {
			return nil
		}
		units := make([]uint16, size/2)
		base, _, _ := procGlobalLock.Call(handle)
		if base == 0 {
			return errors.New("winsys: 无法读取剪贴板内容")
		}
		defer procGlobalUnlock.Call(handle)
		// Copies through an unsafe.Pointer instead of casting the handle.
		procRtlMoveMemory.Call(uintptr(unsafe.Pointer(&units[0])), base, size)
		text, ok = trimAtNUL(units), true
		return nil
	})
	if err != nil {
		return "", false
	}
	return text, ok
}

// ClearClipboardIfEqual empties the clipboard only while it still holds text.
// A secret copied 45 s ago must not wipe whatever the user copied since.
func ClearClipboardIfEqual(text string) bool {
	current, ok := ClipboardText()
	if !ok || current != text {
		return false
	}
	return withClipboard(func() error {
		procEmptyClipboard.Call()
		return nil
	}) == nil
}

// withClipboard opens the clipboard, retrying briefly: another app holding it
// open is routine, not an error worth surfacing straight away.
func withClipboard(fn func() error) error {
	var last error
	for attempt := 0; attempt < 10; attempt++ {
		ok, _, callErr := procOpenClipboard.Call(0)
		if ok != 0 {
			defer procCloseClipboard.Call()
			return fn()
		}
		last = callErr
		time.Sleep(20 * time.Millisecond)
	}
	return fmt.Errorf("winsys: 剪贴板正被其他程序占用（%v）", last)
}

func setClipboardText(text string) error {
	// The trailing NUL is part of the payload, CF_UNICODETEXT requires it.
	encoded := append(utf16.Encode([]rune(text)), 0)
	bytes := uintptr(len(encoded) * 2)
	mem, _, _ := procGlobalAlloc.Call(gmemMoveable, bytes)
	if mem == 0 {
		return errors.New("winsys: 无法为剪贴板分配内存")
	}
	dest, _, _ := procGlobalLock.Call(mem)
	if dest == 0 {
		procGlobalFree.Call(mem)
		return errors.New("winsys: 无法写入剪贴板内存")
	}
	procRtlMoveMemory.Call(dest, uintptr(unsafe.Pointer(&encoded[0])), bytes)
	procGlobalUnlock.Call(mem)
	if ok, _, callErr := procSetClipboardData.Call(cfUnicodeText, mem); ok == 0 {
		// The clipboard did not take ownership, so the memory is still ours.
		procGlobalFree.Call(mem)
		return fmt.Errorf("winsys: 无法写入剪贴板（%v）", callErr)
	}
	return nil
}

func setClipboardFlag(name string) {
	raw, err := syscall.UTF16PtrFromString(name)
	if err != nil {
		return
	}
	id, _, _ := procRegisterFormat.Call(uintptr(unsafe.Pointer(raw)))
	if id == 0 {
		return
	}
	mem, _, _ := procGlobalAlloc.Call(gmemMoveable, 4)
	if mem == 0 {
		return
	}
	dest, _, _ := procGlobalLock.Call(mem)
	if dest == 0 {
		procGlobalFree.Call(mem)
		return
	}
	var off uint32
	procRtlMoveMemory.Call(dest, uintptr(unsafe.Pointer(&off)), 4)
	procGlobalUnlock.Call(mem)
	if ok, _, _ := procSetClipboardData.Call(id, mem); ok == 0 {
		procGlobalFree.Call(mem)
	}
}

func trimAtNUL(units []uint16) string {
	for index, unit := range units {
		if unit == 0 {
			return string(utf16.Decode(units[:index]))
		}
	}
	return string(utf16.Decode(units))
}
