package main

import (
	"fmt"
	"os"
)

var version = "0.0.0"

func main() {
	if len(os.Args) == 2 && os.Args[1] == "version" {
		fmt.Printf("endlessnet-client %s (packaging fixture; not for release)\n", version)
		return
	}
	fmt.Fprintln(os.Stderr, "packaging fixture is not a runnable EndlessNet client")
	os.Exit(2)
}
