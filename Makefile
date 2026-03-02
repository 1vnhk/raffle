-include .env

.PHONY: build format

build:
	@forge build

format:
	@forge fmt
