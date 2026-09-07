SHELL := /bin/bash
.DEFAULT_GOAL := build

INSTALL_DIR ?= $(HOME)/Applications
APP_BUNDLE := .build/Tablin.app

.PHONY: build test install run

build:
	./build

test:
	./test

install: build
	mkdir -p "$(INSTALL_DIR)"
	ditto "$(APP_BUNDLE)" "$(INSTALL_DIR)/Tablin.app"
	codesign --verify --strict "$(INSTALL_DIR)/Tablin.app"
	@printf 'Installed: %s\n' "$(INSTALL_DIR)/Tablin.app"

run:
	open "$(INSTALL_DIR)/Tablin.app"
