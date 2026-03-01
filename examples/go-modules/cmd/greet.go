package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var name string

var greetCmd = &cobra.Command{
	Use:   "greet",
	Short: "Greet someone",
	Run: func(cmd *cobra.Command, args []string) {
		if name == "" {
			name = "World"
		}
		fmt.Printf("Hello, %s!\n", name)
	},
}

func init() {
	greetCmd.Flags().StringVarP(&name, "name", "n", "", "Name to greet")
}
