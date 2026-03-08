-include .env

.PHONY: build format test coverage setup

build:
	@forge build

format:
	@forge fmt

test:
	@forge test -vvv

coverage:
	@forge coverage --report lcov
	genhtml lcov.info -o coverage --branch-coverage --ignore-errors inconsistent
	open coverage/index.html

setup:
	@git config core.hooksPath .githooks
	@echo "Git hooks configured."
