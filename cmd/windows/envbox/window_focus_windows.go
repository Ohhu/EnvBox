//go:build windows

package main

import (
	"syscall"
	"unsafe"
)

var (
	user32                  = syscall.NewLazyDLL("user32.dll")
	procFindWindowW         = user32.NewProc("FindWindowW")
	procShowWindow          = user32.NewProc("ShowWindow")
	procSetForegroundWindow = user32.NewProc("SetForegroundWindow")
)

const swShow = 5

// focusExistingWindow brings the running instance back when EnvBox is started a
// second time. Without it, closing the window to the tray would make a later
// launch look like the app refusing to start: the second process exits because
// the first one owns the vault.
func focusExistingWindow(title string) {
	name, err := syscall.UTF16PtrFromString(title)
	if err != nil {
		return
	}
	hwnd, _, _ := procFindWindowW.Call(0, uintptr(unsafe.Pointer(name)))
	if hwnd == 0 {
		return
	}
	procShowWindow.Call(hwnd, swShow)
	procSetForegroundWindow.Call(hwnd)
}
