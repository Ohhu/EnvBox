//go:build windows

// Command envbox-cli is the command line companion and MCP server entry point.
//
// The installer puts it at <install dir>\bin\envbox.exe, which is the path MCP
// clients should be configured with. GUI and CLI stay separate binaries: the GUI
// is built with -H windowsgui (no console) and a stdio MCP server cannot live in
// a GUI subsystem process.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/Ohhu/EnvBox/internal/appenv"
	"github.com/Ohhu/EnvBox/internal/apperr"
	"github.com/Ohhu/EnvBox/internal/apply"
	"github.com/Ohhu/EnvBox/internal/buildinfo"
	"github.com/Ohhu/EnvBox/internal/mcp"
	"github.com/Ohhu/EnvBox/internal/portable"
	"github.com/Ohhu/EnvBox/internal/shell"
	"github.com/Ohhu/EnvBox/internal/vault"
	"github.com/Ohhu/EnvBox/internal/winsys"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}
	switch os.Args[1] {
	case "version", "--version", "-v":
		cmdVersion()
	case "describe":
		cmdDescribe(os.Args[2:])
	case "profiles":
		cmdProfiles()
	case "apply":
		cmdApply(os.Args[2:])
	case "deactivate":
		cmdDeactivate()
	case "exec":
		cmdExec(os.Args[2:])
	case "mcp":
		cmdMCP()
	case "policy":
		cmdPolicy(os.Args[2:])
	case "shell":
		cmdShell(os.Args[2:])
	case "update":
		cmdUpdate(os.Args[2:])
	case "import":
		cmdImport(os.Args[2:])
	case "uninstall-cleanup":
		cmdUninstallCleanup()
	case "help", "--help", "-h":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "未知命令：%s\n\n", os.Args[1])
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprint(os.Stderr, `envbox — EnvBox 命令行与 MCP 入口

用法：
  envbox version                     版本与构建信息
  envbox profiles                    列出配置（不含变量值）
  envbox describe [KEY...]           输出变量长度与指纹，绝不输出明文
  envbox apply [配置名或ID]          把配置写入当前用户环境并记录激活状态
  envbox deactivate                  移除上次激活写入的变量
  envbox exec [--] <命令> [参数...]   在激活配置的环境里执行命令
  envbox mcp                         MCP stdio 服务器
  envbox policy [--show|--enable|--disable|--allow-reveal|--deny-reveal]
  envbox shell <status|install|uninstall>
  envbox update <check|download|install|pending|settings>
    settings [--check off|daily|weekly] [--skip-version <版本>] [--clear-skip]
  envbox import <file.envbox> --password <密码>   导入其他平台导出的 .envbox
  envbox uninstall-cleanup           清除自启动项等注册表残留（安装器卸载时调用）
`)
}

func cmdVersion() {
	fmt.Printf("EnvBox %s\n", buildinfo.Version)
	fmt.Printf("  build     %s\n", buildinfo.BuildNumber)
	fmt.Printf("  commit    %s\n", buildinfo.Commit)
	fmt.Printf("  built     %s\n", buildinfo.BuildDate)
	fmt.Printf("  channel   %s\n", buildinfo.Channel)
	fmt.Printf("  windows   amd64\n")
	fmt.Printf("  update    %s\n", buildinfo.UpdateRepo)
	if buildinfo.SigningConfigured() {
		fmt.Printf("  signer    %s\n", buildinfo.SignerThumbprint)
	} else {
		fmt.Printf("  signer    (未签名构建)\n")
	}
}

func mustStore() *vault.Store {
	store, err := vault.NewStore()
	if err != nil {
		fmt.Fprintln(os.Stderr, "初始化配置库失败："+apperr.User(err))
		os.Exit(1)
	}
	return store
}

func newProvider() *appenv.Provider {
	provider, err := appenv.NewProvider()
	if err != nil {
		fmt.Fprintln(os.Stderr, "初始化失败："+apperr.User(err))
		os.Exit(1)
	}
	return provider
}

func newApplyService() *apply.Service {
	integration, err := shell.New()
	if err != nil {
		fmt.Fprintln(os.Stderr, "初始化 Shell 集成失败："+apperr.User(err))
		os.Exit(1)
	}
	return &apply.Service{
		Store:     mustStore(),
		Env:       winsys.NewConfigurableEnvStore(),
		Broadcast: winsys.Broadcaster(),
		Shell:     integration,
	}
}

func cmdProfiles() {
	payload, err := newProvider().Payload()
	if err != nil {
		fmt.Fprintln(os.Stderr, "读取配置库失败："+apperr.User(err))
		os.Exit(1)
	}
	type row struct {
		ID        string `json:"id"`
		Name      string `json:"name"`
		Variables int    `json:"variables"`
		Secrets   int    `json:"secrets"`
		Active    bool   `json:"active"`
	}
	activeID := ""
	if payload.ActiveProfileID != nil {
		activeID = *payload.ActiveProfileID
	}
	out := make([]row, 0, len(payload.Profiles))
	for _, p := range payload.Profiles {
		out = append(out, row{ID: p.ID, Name: p.Name, Variables: len(p.Variables), Secrets: p.SecretCount(), Active: p.ID == activeID})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	encode(out)
}

func cmdDescribe(args []string) {
	description, err := newProvider().Describe(args)
	if err != nil {
		fmt.Fprintln(os.Stderr, "读取配置库失败："+apperr.User(err))
		os.Exit(1)
	}
	encode(description)
}

func cmdApply(args []string) {
	reference := ""
	if len(args) > 0 {
		reference = args[0]
	}
	report, err := newApplyService().Activate(reference)
	if err != nil {
		fmt.Fprintln(os.Stderr, "应用失败："+apperr.User(err))
		if report != nil {
			encode(report)
		}
		os.Exit(1)
	}
	encode(report)
}

func cmdDeactivate() {
	report, err := newApplyService().Deactivate()
	if err != nil {
		fmt.Fprintln(os.Stderr, "停用失败："+apperr.User(err))
		os.Exit(1)
	}
	encode(report)
}

func cmdExec(args []string) {
	if len(args) > 0 && args[0] == "--" {
		args = args[1:]
	}
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "用法：envbox exec [--] <命令> [参数...]")
		os.Exit(1)
	}
	provider := newProvider()
	env, err := provider.MergedEnvironment()
	if err != nil {
		fmt.Fprintln(os.Stderr, "读取配置库失败："+apperr.User(err))
		os.Exit(1)
	}
	if err := runCommand(env, args); err != nil {
		os.Exit(exitCodeOf(err))
	}
}

func cmdMCP() {
	server := &mcp.Server{
		Env:     newProvider(),
		Policy:  mcp.LoadPolicy,
		Version: buildinfo.Version,
		Err:     os.Stderr,
	}
	if err := server.Serve(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "MCP 会话结束："+apperr.User(err))
		os.Exit(1)
	}
}

func cmdPolicy(args []string) {
	policy := mcp.LoadPolicy()
	if len(args) == 0 {
		encode(policy)
		return
	}
	for _, arg := range args {
		switch arg {
		case "--show":
		case "--enable":
			policy.Enabled = true
		case "--disable":
			policy.Enabled = false
		case "--allow-reveal":
			policy.AllowReveal = true
		case "--deny-reveal":
			policy.AllowReveal = false
		default:
			fmt.Fprintf(os.Stderr, "未知参数：%s\n", arg)
			os.Exit(1)
		}
	}
	if err := mcp.SavePolicy(policy); err != nil {
		fmt.Fprintln(os.Stderr, "保存策略失败："+apperr.User(err))
		os.Exit(1)
	}
	encode(policy)
}

func cmdShell(args []string) {
	integration, err := shell.New()
	if err != nil {
		fmt.Fprintln(os.Stderr, "初始化 Shell 集成失败："+apperr.User(err))
		os.Exit(1)
	}
	action := "status"
	if len(args) > 0 {
		action = args[0]
	}
	switch action {
	case "status":
		encode(integration.Status())
	case "install":
		if err := integration.Install(); err != nil {
			fmt.Fprintln(os.Stderr, "安装 Shell 集成失败："+apperr.User(err))
			os.Exit(1)
		}
		// The GUI writes the same snapshot on install; without it a new terminal
		// sources nothing even though the profile block exists.
		payload, err := mustStore().Load()
		if err != nil {
			fmt.Fprintln(os.Stderr, "读取配置库失败："+apperr.User(err))
			os.Exit(1)
		}
		if active := payload.ActiveProfile(); active != nil {
			if err := integration.WriteActivation(*active); err != nil {
				fmt.Fprintln(os.Stderr, "写入激活快照失败："+apperr.User(err))
				os.Exit(1)
			}
		}
		encode(integration.Status())
	case "uninstall":
		if err := integration.Uninstall(); err != nil {
			fmt.Fprintln(os.Stderr, "移除 Shell 集成失败："+apperr.User(err))
			os.Exit(1)
		}
		encode(integration.Status())
	default:
		fmt.Fprintf(os.Stderr, "未知操作：%s（status|install|uninstall）\n", action)
		os.Exit(1)
	}
}

func cmdUninstallCleanup() {
	failures := 0
	if err := winsys.NewUserAutostart().Disable(); err != nil {
		fmt.Fprintln(os.Stderr, "清除自启动项失败："+apperr.User(err))
		failures++
	}
	integration, err := shell.New()
	if err != nil {
		fmt.Fprintln(os.Stderr, "定位 Shell 集成失败："+apperr.User(err))
		failures++
	} else {
		if err := integration.Uninstall(); err != nil {
			fmt.Fprintln(os.Stderr, "移除 Shell 集成失败："+apperr.User(err))
			failures++
		}
		if err := integration.RemoveActivation(); err != nil {
			fmt.Fprintln(os.Stderr, "删除激活快照失败："+apperr.User(err))
			failures++
		}
	}
	if failures > 0 {
		os.Exit(1)
	}
	fmt.Println("已清除 EnvBox 注册的启动项与 Shell 集成")
}

func encode(v any) {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	_ = encoder.Encode(v)
}

func exitCodeOf(err error) int {
	if code, ok := err.(interface{ ExitCode() int }); ok {
		return code.ExitCode()
	}
	return 1
}

// describeFileError turns an os error into something the user can act on.
func describeFileError(err error, path string) string {
	switch {
	case errors.Is(err, os.ErrNotExist):
		return "找不到文件 " + path
	case errors.Is(err, os.ErrPermission):
		return "没有权限读取 " + path
	default:
		return "无法读取 " + path
	}
}

// cmdImport merges an exported .envbox archive into the local vault. Profiles are
// appended; name collisions are rejected by model.ValidateUniqueNames.
func cmdImport(args []string) {
	var source, passphrase string
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--password":
			if i+1 >= len(args) {
				fail("--password 需要取值")
			}
			passphrase = args[i+1]
			i++
		default:
			if source == "" {
				source = args[i]
			}
		}
	}
	if source == "" || passphrase == "" {
		fail("用法：envbox import <file.envbox> --password <密码>")
	}

	data, err := os.ReadFile(source)
	if err != nil {
		failText("读取导入文件失败：" + describeFileError(err, source))
	}
	archive, err := portable.Import(data, passphrase)
	if err != nil {
		failText(apperr.User(err))
	}

	store := mustStore()
	payload, err := store.Load()
	if err != nil {
		failText(apperr.User(err))
	}

	// Check before writing: model validation only reports "配置 ID 重复", which does
	// not say which profile is in the way.
	names := make(map[string]struct{}, len(payload.Profiles))
	ids := make(map[string]struct{}, len(payload.Profiles))
	for _, profile := range payload.Profiles {
		names[strings.ToLower(profile.Normalized().Name)] = struct{}{}
		ids[profile.ID] = struct{}{}
	}
	for _, profile := range archive.Profiles {
		if _, clash := names[strings.ToLower(profile.Normalized().Name)]; clash {
			failText("配置「" + profile.Normalized().Name + "」已存在，请先改名或删除后再导入")
		}
		if _, clash := ids[profile.ID]; clash {
			failText("文件里的配置「" + profile.Normalized().Name + "」与本地同 ID，请先在导出方改名或删除")
		}
	}

	payload.Profiles = append(payload.Profiles, archive.Profiles...)
	if err := store.Save(payload); err != nil {
		failText("写入配置库失败：" + apperr.User(err))
	}
	fmt.Printf("已导入 %d 个配置\n", len(archive.Profiles))
}
