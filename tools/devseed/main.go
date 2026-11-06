//go:build windows

// Command devseed writes a demo vault so the CLI, MCP server and (later) the GUI
// can be exercised without clicking through the UI. Development builds only:
// it refuses to run when the binary was built for production.
//
//	go run ./tools/devseed -dir .build/e2e-config
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/Ohhu/EnvBox/internal/buildinfo"
	"github.com/Ohhu/EnvBox/internal/model"
	"github.com/Ohhu/EnvBox/internal/vault"
	"github.com/Ohhu/EnvBox/internal/winsys"
)

func main() {
	dir := flag.String("dir", "", "配置目录（等价于设置 ENVBOX_CONFIG_DIR）")
	flag.Parse()

	if buildinfo.Channel == "production" {
		fmt.Fprintln(os.Stderr, "devseed：拒绝在 production 构建上生成演示数据")
		os.Exit(1)
	}
	if *dir != "" {
		os.Setenv(winsys.ConfigDirEnv, *dir)
	}
	configDir, err := winsys.EnsureConfigDir()
	if err != nil {
		fmt.Fprintf(os.Stderr, "devseed：无法创建配置目录：%v\n", err)
		os.Exit(1)
	}

	store := &vault.Store{
		Path:     filepath.Join(configDir, "vault.envbox"),
		Provider: &vault.DPAPIProvider{Path: filepath.Join(configDir, "vault.key")},
	}

	now := model.Now()
	work := model.EnvProfile{
		ID: "11111111-1111-4111-8111-111111111111", Name: "工作环境", Note: "演示数据", Tint: "ocean",
		Symbol: "briefcase.fill", CreatedAt: now, UpdatedAt: now,
		Variables: []model.EnvVariable{
			{ID: "v1", Key: "DEMO_TOKEN", Value: "demo-token-value", IsEnabled: true, IsSecret: true, Note: "示例密钥"},
			{ID: "v2", Key: "DEMO_REGION", Value: "cn-north-1", IsEnabled: true},
			{ID: "v3", Key: "DEMO_DISABLED", Value: "not-applied", IsEnabled: false},
		},
	}
	personal := model.EnvProfile{
		ID: "22222222-2222-4222-8222-222222222222", Name: "个人环境", Note: "", Tint: "aurora",
		Symbol: "shippingbox.fill", CreatedAt: now, UpdatedAt: now,
		Variables: []model.EnvVariable{
			{ID: "w1", Key: "DEMO_LOCALE", Value: "zh-CN", IsEnabled: true},
		},
	}

	payload := model.EmptyVaultPayload(now)
	payload.Profiles = []model.EnvProfile{work, personal}
	active := work.ID
	payload.ActiveProfileID = &active
	fingerprint := work.Fingerprint()
	payload.AppliedFingerprint = &fingerprint
	payload.AppliedKeys = []string{"DEMO_TOKEN", "DEMO_REGION"}

	if err := store.Save(payload); err != nil {
		fmt.Fprintf(os.Stderr, "devseed：写入配置库失败：%v\n", err)
		os.Exit(1)
	}
	fmt.Printf("已写入演示配置库：%s\n", store.Path)
	fmt.Printf("  配置 2 个，激活：%s，已应用变量 2 个\n", work.Name)
}
