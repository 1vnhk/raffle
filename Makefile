-include .env

.PHONY: build format test coverage

build:
	@forge build

format:
	@forge fmt

test:
	@forge test -vvv

coverage:
	@forge coverage --report lcov
	genhtml lcov.info -o coverage --branch-coverage
	open coverage/index.html
