AIT := ./ait.sh

.DEFAULT_GOAL := help

.PHONY: help install list validate test update

help: ## Show this help
	@printf '\n\033[1mAI Tools\033[0m\n\n'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@printf '\n'

install: ## Bootstrap: install the ait CLI to your PATH
	@./install.sh

list: ## List every agent, skill and hook, and the assistants that support them
	@$(AIT) list

validate: ## Lint every item for every assistant it opts into
	@$(AIT) validate

test: ## Run the test suite (tests/run.sh)
	@bash tests/run.sh

update: ## Pull latest changes from the ai-tools repo
	@$(AIT) update
