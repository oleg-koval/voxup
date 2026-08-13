.DEFAULT_GOAL := help

.PHONY: help lint doctor

help:
	@echo "Targets:"
	@echo "  lint    - run shellcheck + shfmt -d on install.sh"
	@echo "  doctor  - run install.sh --doctor"

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck install.sh; \
	else \
		echo "warning: shellcheck not installed, skipping"; \
	fi
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -d install.sh; \
	else \
		echo "warning: shfmt not installed, skipping"; \
	fi

doctor:
	bash install.sh --doctor
