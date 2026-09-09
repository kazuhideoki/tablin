SHELL := /bin/bash
.DEFAULT_GOAL := help

INSTALL_DIR ?= $(HOME)/Applications
APP_BUNDLE := .build/Tablin.app
DEV_SUFFIX = $(shell printf '%s' "$$(pwd -P)" | shasum -a 256 | cut -c1-12)
DEV_APP_BUNDLE = .build/dev/Tablin Dev $(DEV_SUFFIX).app

.PHONY: help build dev build-dev run-dev test install run

help: # Show available targets
	@awk 'BEGIN {FS = ":.*# "} /^[a-zA-Z_-]+:.*# / {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf '\nOverride the install location with INSTALL_DIR=/path/to/Applications.\n'

build: # Build Tablin
	./build

build-dev: # Build the development app for this worktree
	./build --dev

run-dev: # Open the development app for this worktree without building
	@test -d "$(DEV_APP_BUNDLE)" || { printf 'Development app not found. Run make build-dev or make dev first.\n' >&2; exit 1; }
	open "$(DEV_APP_BUNDLE)"

dev: # Build and open the development app for this worktree
	./dev

test: # Run tests and lint checks
	./test

install: build # Build and install Tablin (default: ~/Applications)
	mkdir -p "$(INSTALL_DIR)"
	ditto "$(APP_BUNDLE)" "$(INSTALL_DIR)/Tablin.app"
	codesign --verify --strict "$(INSTALL_DIR)/Tablin.app"
	@printf 'Installed: %s\n' "$(INSTALL_DIR)/Tablin.app"

run: # Open the installed Tablin app
	open "$(INSTALL_DIR)/Tablin.app"
