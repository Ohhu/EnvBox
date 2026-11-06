//go:build windows

package main

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/Ohhu/EnvBox/internal/core/apperr"
	"github.com/Ohhu/EnvBox/internal/windows/settings"
	"github.com/Ohhu/EnvBox/internal/windows/update"
	"github.com/Ohhu/EnvBox/internal/windows/winsys"
)

// cmdUpdate exposes the updater to scripts and to manual verification. The GUI
// uses the same service, so behaviour cannot drift between the two.
// requireInstalled keeps the CLI and GUI on the same rule: development builds
// never talk to the update service.
func requireInstalled() {
	if !winsys.IsInstalled() {
		failText("开发态不参与更新：请使用安装后的 EnvBox")
	}
}

func cmdUpdate(args []string) {
	action := "check"
	if len(args) > 0 {
		action = args[0]
		args = args[1:]
	}

	switch action {
	case "check":
		requireInstalled()
		checkForUpdate(args)
	case "download":
		requireInstalled()
		downloadUpdate(args)
	case "install":
		requireInstalled()
		installUpdate()
	case "pending":
		pending, err := update.ReadPending()
		if err != nil {
			fail("读取待安装记录失败：%v", err)
		}
		if pending == nil {
			fmt.Println("没有待安装的更新")
			return
		}
		encode(pending)
	case "settings":
		updateSettings(args)
	default:
		fmt.Fprintf(os.Stderr, "未知操作：%s（check|download|install|pending|settings）\n", action)
		os.Exit(1)
	}
}

func checkForUpdate(args []string) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	service := update.NewService()
	available, err := service.Check(ctx)
	jsonOutput := hasFlag(args, "--json")
	if err != nil {
		if jsonOutput {
			encode(map[string]string{"error": apperr.User(err)})
		} else {
			fmt.Println(apperr.User(err))
		}
		if !update.IsNoOp(err) {
			os.Exit(1)
		}
		return
	}
	if jsonOutput {
		encode(available)
		return
	}
	fmt.Printf("发现新版本 %s（当前 %s）\n", available.Version, available.Current)
	if available.HTMLURL != "" {
		fmt.Printf("  发布页 %s\n", available.HTMLURL)
	}
}

func downloadUpdate(args []string) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()

	service := update.NewService()
	available, err := service.Check(ctx)
	if err != nil {
		if update.IsNoOp(err) {
			fmt.Println(apperr.User(err))
			return
		}
		fail("检查更新失败：%v", err)
	}
	pending, err := service.Download(ctx, available)
	if err != nil {
		fail("下载安装包失败：%v", err)
	}
	encode(pending)
}

func installUpdate() {
	pending, err := update.ReadPending()
	if err != nil {
		fail("读取待安装记录失败：%v", err)
	}
	if pending == nil {
		fail("没有待安装的更新，请先执行 envbox update download")
	}
	if err := update.NewService().Install(pending); err != nil {
		fail("启动安装包失败：%v", err)
	}
	fmt.Printf("安装程序已启动，EnvBox 将退出以完成更新到 %s\n", pending.To)
}

// updateSettings edits the updater section, keeping UI and CLI on one file.
func updateSettings(args []string) {
	current := settings.Load()
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--check":
			if i+1 >= len(args) {
				fail("--check 需要取值 off|daily|weekly")
			}
			i++
			value := settings.UpdateCheck(args[i])
			switch value {
			case settings.CheckOff, settings.CheckDaily, settings.CheckWeekly:
				current.Update.Check = value
			default:
				fail("--check 只接受 off|daily|weekly")
			}
		case "--skip-version":
			if i+1 >= len(args) {
				fail("--skip-version 需要版本号")
			}
			i++
			current.Update.SkippedVersion = strings.TrimSpace(args[i])
		case "--clear-skip":
			current.Update.SkippedVersion = ""
		default:
			fail("未知参数：%s", args[i])
		}
	}
	if err := current.Save(); err != nil {
		fail("保存设置失败：%v", err)
	}
	encode(current)
}

func hasFlag(args []string, flag string) bool {
	for _, arg := range args {
		if arg == flag {
			return true
		}
	}
	return false
}

// failText reports an already formatted message; use it when the text comes from
// an error instead of a literal, so vet does not treat it as a format string.
func failText(message string) {
	fmt.Fprintln(os.Stderr, apperr.FromString(message))
	os.Exit(1)
}

func fail(format string, values ...any) {
	fmt.Fprintln(os.Stderr, apperr.FromString(fmt.Sprintf(format, values...)))
	os.Exit(1)
}
