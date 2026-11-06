//go:build windows

// Command envbox is the EnvBox desktop application.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"

	"github.com/Ohhu/EnvBox/internal/core/apperr"
	"github.com/Ohhu/EnvBox/internal/core/buildinfo"
	"github.com/Ohhu/EnvBox/internal/windows/winsys"
	"github.com/Ohhu/EnvBox/shared/ui"
)

// quitRequested reports whether this launch only asks the running instance to
// exit. The installer sets the quit event directly; this flag is for scripts and
// for anyone who wants to stop the tray app from a terminal.
func quitRequested() bool {
	for _, arg := range os.Args[1:] {
		if arg == "--quit" {
			return true
		}
	}
	return false
}

// updatedFlag reports whether the installer started us with --updated, so the log
// records the upgrade handoff.
func updatedFlag() bool {
	for _, arg := range os.Args[1:] {
		if arg == "--updated" {
			return true
		}
	}
	return false
}

// writeStartupLog appends one line to %LOCALAPPDATA%\EnvBox\startup.log. The GUI
// has no console, so this file is the only place a non-fatal failure survives.
func writeStartupLog(message string) {
	dir, err := winsys.LocalAppDataDir()
	if err != nil {
		return
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return
	}
	file, err := os.OpenFile(filepath.Join(dir, "startup.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	defer file.Close()
	fmt.Fprintf(file, "%s %s\n", time.Now().Format(time.RFC3339), message)
}

// fatal reports a startup failure the user can see and then exits.
func fatal(err error) {
	message := apperr.User(err)
	writeStartupLog(message)
	winsys.ShowError("EnvBox 无法启动", message+"\n\n详细信息见 %LOCALAPPDATA%\\EnvBox\\startup.log")
	os.Exit(1)
}

func main() {
	if quitRequested() {
		// Signal before touching the mutex: this process must never look like a
		// second instance, and it must not create the quit event itself.
		winsys.RequestQuit()
		return
	}
	release, alreadyRunning, err := winsys.AcquireSingleInstance()
	if err != nil {
		fatal(err)
	}
	defer release()
	if alreadyRunning {
		// The other instance owns the vault, so this process exits; it does bring
		// the running window back first, because otherwise a launch after closing
		// to the tray would look like nothing happened.
		focusExistingWindow("EnvBox " + buildinfo.Version)
		return
	}

	if updated := updatedFlag(); updated {
		writeStartupLog("更新已安装，启动新版本")
	}

	configDir, err := winsys.EnsureConfigDir()
	if err != nil {
		fatal(err)
	}
	webAssets, err := ui.Files()
	if err != nil {
		fatal(err)
	}

	var app *application.App
	var mainWindow *application.WebviewWindow
	service, err := NewApp(func(action string) {
		switch action {
		case "quit":
			if app != nil {
				app.Quit()
			}
		case "window-minimise":
			if mainWindow != nil {
				mainWindow.Minimise()
			}
		case "window-toggle-maximise":
			if mainWindow != nil {
				mainWindow.ToggleMaximise()
			}
		case "window-close":
			if mainWindow != nil {
				mainWindow.Hide()
			}
		}
	})
	if err != nil {
		fatal(err)
	}

	app = application.New(application.Options{
		Name:        "EnvBox",
		Description: "Windows 环境变量管理",
		Services:    []application.Service{application.NewService(service)},
		Assets: application.AssetOptions{
			Handler: newHandler(service, application.BundledAssetFileServer(webAssets)),
		},
		Windows: application.WindowsOptions{
			// WebView2 refuses to start when it cannot create its user data folder;
			// keeping it inside the config directory makes that explicit and keeps
			// browser state next to the rest of EnvBox's data.
			WebviewUserDataPath: filepath.Join(configDir, "webview"),
		},
	})

	startURL := "/"
	// Screenshot helpers for development only; release builds ignore them.
	if view := os.Getenv("ENVBOX_START_VIEW"); view != "" && buildinfo.Channel != "production" {
		startURL += "?view=" + view
	}
	// Lets a dev build boot straight into the shared UI's demo data, so the real
	// WebView2 shell can be inspected without creating a vault first.
	if raw := os.Getenv("ENVBOX_START_URL"); raw != "" && buildinfo.Channel != "production" {
		startURL = raw
	}

	mainWindow = app.Window.NewWithOptions(application.WebviewWindowOptions{
		Title: "EnvBox " + buildinfo.Version,
		// Same default and minimum as the macOS window (EnvBoxScene.swift).
		Width:     1180,
		Height:    760,
		MinWidth:  980,
		MinHeight: 640,
		URL:       startURL,
		// Frameless: the shared UI draws its own 38px title strip so the window
		// edge is continuous with the content, the same way the macOS build uses
		// .hiddenTitleBar. Wails keeps the Aero shadow and Win11 rounded corners.
		Frameless: true,
	})

	// Closing the window leaves EnvBox in the notification area, the same contract
	// the macOS build has with the menu bar: the app runs until it is told to quit.
	mainWindow.OnWindowEvent(events.Common.WindowClosing, func(event *application.WindowEvent) {
		event.Cancel()
		mainWindow.Hide()
	})
	envTray := newTray(app, service, mainWindow)
	onStateChanged = envTray.applyState

	// The installer signals this event before overwriting files. Without it an
	// upgrade would stop at "please close EnvBox" and make the user quit the tray
	// app by hand. Started right before Run so a signal cannot arrive before the
	// event loop exists.
	quitSignal, stopListening, listenErr := winsys.ListenForQuit()
	if listenErr != nil {
		// Not fatal: the window works, only the automatic close during an upgrade
		// is lost, and the installer falls back to asking.
		writeStartupLog("退出信号初始化失败：" + apperr.User(listenErr))
	} else {
		defer stopListening()
		go func() {
			<-quitSignal
			writeStartupLog("收到退出信号，正在退出以便安装程序覆盖文件")
			app.Quit()
		}()
	}

	if err := service.StartupMaintenance(); err != nil {
		// Not fatal: the window still works and the next launch retries, but the
		// failure must leave a trace because stderr goes nowhere.
		writeStartupLog("更新清理失败：" + apperr.User(err))
	}
	go service.AutoCheckIfDue()

	if err := app.Run(); err != nil {
		fatal(err)
	}
}
