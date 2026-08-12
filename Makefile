AIT := ./ait

.DEFAULT_GOAL := help

.PHONY: help install list update

help: ## Show this help
	@printf '\n\033[1mAI Tools\033[0m\n\n'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@printf '\n'

install: ## Bootstrap: install the ait CLI to your PATH
	@./install.sh

list: ## List all available agents, skills, hooks, and Copilot items
	@$(AIT) list

update: ## Pull latest changes from the ai-tools repo
	@$(AIT) update
