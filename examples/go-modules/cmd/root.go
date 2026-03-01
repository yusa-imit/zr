package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "gocli",
	Short: "A simple CLI application built with Go and Cobra",
	Long: `gocli is a demonstration CLI application showing how to use
zr for Go project task automation and orchestration.`,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("Hello from gocli! Use --help to see available commands.")
	},
}

func Execute() error {
	return rootCmd.Execute()
}

func init() {
	rootCmd.AddCommand(versionCmd)
	rootCmd.AddCommand(greetCmd)
}
