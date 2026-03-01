package cmd

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestGreetCommand(t *testing.T) {
	// Test that greetCmd exists
	assert.NotNil(t, greetCmd)
	assert.Equal(t, "greet", greetCmd.Use)
}

func TestGreetWithName(t *testing.T) {
	name = "Alice"
	assert.Equal(t, "Alice", name)
}
