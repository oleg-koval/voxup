.DEFAULT_GOAL := help

.PHONY: help lint test doctor

help:
	@echo "Targets:"
	@echo "  lint    - run shellcheck + shfmt -d on all scripts"
	@echo "  test    - run tests/test-claude-hook.sh"
	@echo "  doctor  - run install.sh --doctor"

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck install.sh hooks/*.sh tests/*.sh; \
	else \
		echo "warning: shellcheck not installed, skipping"; \
	fi
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -d install.sh hooks/*.sh tests/*.sh; \
	else \
		echo "warning: shfmt not installed, skipping"; \
	fi

test:
	bash tests/test-claude-hook.sh

doctor:
	bash install.sh --doctor
