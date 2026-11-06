package apperr

import (
	"errors"
	"testing"
)

func TestFromStringStripsKnownPrefixes(t *testing.T) {
	cases := map[string]string{
		"update: 已是最新版本":           "已是最新版本",
		"settings: 更新检查已关闭":        "更新检查已关闭",
		"update: update: 双重前缀":     "双重前缀",
		"vault: 打开配置库失败: 权限不足":     "打开配置库失败: 权限不足",
		"读取配置库失败：vault: 配置库文件结构无效": "读取配置库失败：配置库文件结构无效",
		"写入配置库失败：model: 配置名重复：dup": "写入配置库失败：配置名重复：dup",
		"普通消息: 保持原样":               "普通消息: 保持原样",
	}
	for input, want := range cases {
		if got := FromString(input); got != want {
			t.Errorf("%q → %q，期望 %q", input, got, want)
		}
	}
}

func TestUserHandlesNilAndErrors(t *testing.T) {
	if got := User(nil); got != "" {
		t.Errorf("nil 应为空串，得到 %q", got)
	}
	if got := User(errors.New("model: 配置名重复：x")); got != "配置名重复：x" {
		t.Errorf("unexpected %q", got)
	}
}
