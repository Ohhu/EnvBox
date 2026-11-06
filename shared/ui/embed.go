// Package ui embeds the shared web UI.
//
// Windows serves these files straight out of the executable; macOS copies the
// same directory into the app bundle (Scripts/macos/build-app.sh). Keeping the
// bytes in one place is the point of the layout: cmd/ only hosts them.
package ui

import (
	"embed"
	"io/fs"
)

//go:embed all:assets
var assets embed.FS

// Files returns the UI rooted at index.html.
func Files() (fs.FS, error) {
	return fs.Sub(assets, "assets")
}
