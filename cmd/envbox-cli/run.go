//go:build windows

package main

import (
	"os"
	"os/exec"
)

// runCommand executes argv with the merged environment, wiring stdio straight
// through so interactive tools behave normally.
func runCommand(env []string, argv []string) error {
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Env = env
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
