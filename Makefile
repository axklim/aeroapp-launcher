# Thin wrappers around build.sh and test.sh. The scripts stay the source of
# truth — the Homebrew formula and a bare shell need no make.

DIST := dist
BIN  := $(DIST)/AeroAppLauncher.app/Contents/MacOS/AeroAppLauncher

.PHONY: build test install run clean

build:
	./build.sh $(DIST)

test:
	./test.sh

# What the formula does, minus the bin/ symlink: ~/Applications/AeroAppLauncher.app
install:
	./build.sh ~/Applications

# Foreground daemon, logging to the terminal. Ctrl-C to stop.
run: build
	$(BIN)

clean:
	rm -rf $(DIST) "$${TMPDIR:-/tmp}/aeroapp-launcher-tests"
