// Package apperr turns internal errors into text a user can act on.
//
// Errors inside EnvBox carry a "pkg: " prefix so logs stay greppable; the UI and
// CLI strip it before showing the message.
package apperr

import "strings"

var prefixes = map[string]struct{}{
	"update": {}, "apply": {}, "vault": {}, "portable": {}, "winsys": {},
	"settings": {}, "cryptox": {}, "shell": {}, "model": {}, "mcp": {}, "appenv": {},
}

// User returns the message without leading package prefixes.
func User(err error) string {
	if err == nil {
		return ""
	}
	return FromString(err.Error())
}

// FromString strips "pkg: " prefixes, including ones that appear after a Chinese
// separator such as "读取配置库失败：vault: 结构无效".
func FromString(message string) string {
	for name := range prefixes {
		message = strings.ReplaceAll(message, name+": ", "")
	}
	return message
}
