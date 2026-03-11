-include .env

.PHONY: build format test-unit coverage setup test-sepolia

build:
	@forge build

format:
	@forge fmt

test-unit:
	@forge test -vvv

test-sepolia:
	forge test --fork-url $(SEPOLIA_RPC_URL) -vvv

coverage:
	@forge coverage --report lcov
	genhtml lcov.info -o coverage --branch-coverage --ignore-errors inconsistent
	open coverage/index.html

setup:
	@git config core.hooksPath .githooks
	@echo "Git hooks configured."
