HUGO := hugo
BASE_URL ?=
DESTINATION := docs

ARGS := --minify --destination $(DESTINATION)
ifneq ($(BASE_URL),)
	ARGS += --baseURL $(BASE_URL)
endif

.PHONY: all build serve clean help

all: build

build: ## Build the site. Usage: make build [BASE_URL=https://example.com/]
	$(HUGO) $(ARGS)

serve: ## Serve the site locally with drafts enabled.
	$(HUGO) server -D

clean: ## Clean the build directory.
	rm -rf $(DESTINATION)

help: ## Show this help message.
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
