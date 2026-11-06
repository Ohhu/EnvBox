//go:build windows

package main

import (
	_ "embed"

	"github.com/wailsapp/wails/v3/pkg/application"

	"github.com/Ohhu/EnvBox/internal/core/apperr"
)

//go:embed assets/tray-32.png
var trayIcon []byte

// onStateChanged lets the HTTP handler hand a fresh state payload to the tray
// without loading the vault a second time. main installs it before serving.
var onStateChanged = func(*StateView) {}

// tray is the Windows counterpart of the macOS menu bar item: profiles switch
// from the notification area, the window can be dismissed without quitting, and
// quitting is an explicit menu action rather than a side effect of closing.
type tray struct {
	app    *application.App
	svc    *App
	window *application.WebviewWindow
	item   *application.SystemTray
	menu   *application.Menu
}

func newTray(app *application.App, svc *App, window *application.WebviewWindow) *tray {
	t := &tray{app: app, svc: svc, window: window, menu: application.NewMenu()}
	t.item = app.SystemTray.New()
	t.item.SetIcon(trayIcon)
	t.item.SetTooltip("EnvBox")
	t.item.OnClick(t.toggle)
	t.item.SetMenu(t.menu)
	t.refresh()
	return t
}

// toggle shows the window when the icon is clicked and hides it on a second
// click, so the tray icon is the way back to the main window.
func (t *tray) toggle() {
	if t.window.IsVisible() {
		t.window.Hide()
		return
	}
	t.show()
}

func (t *tray) show() {
	t.window.Show()
	t.window.Focus()
}

// refresh reloads the state so the menu matches the vault right after startup.
func (t *tray) refresh() {
	state, err := t.svc.State()
	if err != nil {
		writeStartupLog("托盘菜单读取状态失败：" + apperr.User(err))
		return
	}
	t.applyState(state)
}

// applyState rebuilds the menu from a payload the caller already has. The menu
// is rebuilt instead of patched because profiles are added and renamed from the
// window while the menu sits in the notification area.
func (t *tray) applyState(state *StateView) {
	t.menu.Clear()

	open := t.menu.Add("打开 EnvBox")
	open.OnClick(func(*application.Context) { t.show() })
	t.menu.AddSeparator()

	if len(state.Profiles) == 0 {
		empty := t.menu.Add("还没有配置")
		empty.SetEnabled(false)
	}
	for _, profile := range state.Profiles {
		id := profile.ID
		item := t.menu.AddRadio(profile.Name, profile.ID == state.ActiveID)
		item.OnClick(func(*application.Context) { t.apply(id) })
	}

	if state.ActiveID != "" {
		t.menu.AddSeparator()
		clear := t.menu.Add("停用当前配置")
		clear.OnClick(func(*application.Context) { t.run("deactivate", "") })
	}

	t.menu.AddSeparator()
	quit := t.menu.Add("退出 EnvBox")
	quit.OnClick(func(*application.Context) { t.app.Quit() })

	t.menu.Update()
}

func (t *tray) apply(id string) { t.run("apply", `{"id":"`+id+`"}`) }

// run dispatches off the menu thread: applying a profile writes the registry and
// broadcasts WM_SETTINGCHANGE, which must not stall the notification area.
func (t *tray) run(action string, payload string) {
	go func() {
		result, err := t.svc.Dispatch(action, payload)
		switch {
		case err != nil:
			writeStartupLog("托盘操作失败（" + action + "）：" + apperr.User(err))
		case !result.OK:
			writeStartupLog("托盘操作失败（" + action + "）：" + result.Message)
		case result.State != nil:
			t.applyState(result.State)
		}
	}()
}
