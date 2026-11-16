package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/mikaib/loreline/go/loreline"
)

const savePath = "save.json"

var input = bufio.NewReader(os.Stdin)

func dialogue(it *loreline.Interpreter, character string, text string, tags []loreline.TextTag, advance func()) {
	text = strings.ReplaceAll(text, "\n", "\n ")

	if character == "" {
		fmt.Printf(" %s\n", text)
	} else {
		name, _ := it.CharacterField(character, "name").(string)
		if name == "" {
			name = character
		}
		fmt.Printf(" %s: %s\n", name, text)
	}

	advance()
}

func choice(it *loreline.Interpreter, options []loreline.ChoiceOption, choose func(index int)) {
	fmt.Println()
	var enabled []int
	for i, option := range options {
		if option.Enabled {
			enabled = append(enabled, i)
			fmt.Printf(" %d. %s\n", len(enabled), option.Text)
		}
	}

	for {
		fmt.Print("\n> ")
		line, err := input.ReadString('\n')
		if err != nil {
			fmt.Println()
			os.Exit(0)
		}
		line = strings.TrimSpace(line)

		if line == "s" {
			save, err := it.Save()
			if err == nil {
				err = os.WriteFile(savePath, []byte(save), 0o644)
			}
			if err != nil {
				fmt.Println("  Could not save:", err)
			} else {
				fmt.Println("  Saved to", savePath)
			}
			continue
		}

		n, err := strconv.Atoi(line)
		if err == nil && n >= 1 && n <= len(enabled) {
			choose(enabled[n-1])
			return
		}
		fmt.Println("  Please enter a valid choice number (or s to save).")
	}
}

func finish(it *loreline.Interpreter) {
	fmt.Println("\n--- End of story ---")
}

func main() {
	resume := flag.Bool("resume", false, "continue from "+savePath)
	flag.Parse()

	script, err := loreline.ParseFile(filepath.Join("story", "CoffeeShop.lor"))
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}

	handlers := loreline.Handlers{Dialogue: dialogue, Choice: choice, Finish: finish}

	fmt.Print("=== CoffeeShop ===\n\n")
	if *resume {
		save, err := os.ReadFile(savePath)
		if err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
		_, err = script.Resume(handlers, string(save), nil)
	} else {
		_, err = script.Play(handlers, nil)
	}

	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}
