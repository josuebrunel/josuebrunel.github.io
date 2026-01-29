.PHONY: help build serve clean new-post deploy init

# Default target
help:
	@echo "Hugo Static Site Generator - Available Commands:"
	@echo ""
	@echo "  make help       - Show this help message"
	@echo "  make init       - Initialize git submodules (themes)"
	@echo "  make build      - Build the Hugo site (generates HTML in public/)"
	@echo "  make serve      - Start Hugo development server"
	@echo "  make clean      - Remove generated files (public/ and resources/)"
	@echo "  make new-post   - Create a new blog post (use TITLE='Post Title')"
	@echo "  make deploy     - Build with production settings"
	@echo ""

# Initialize git submodules (themes)
init:
	@echo "Initializing git submodules..."
	git submodule update --init --recursive

# Build the Hugo site and generate HTML pages
build:
	@echo "Building Hugo site..."
	hugo --minify

# Start the Hugo development server
serve:
	@echo "Starting Hugo development server..."
	hugo server -D

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	rm -rf public resources

# Create a new blog post
# Usage: make new-post TITLE="My Post Title"
new-post:
ifndef TITLE
	@echo "Error: TITLE is required. Usage: make new-post TITLE='My Post Title'"
	@exit 1
endif
	@echo "Creating new post: $(TITLE)"
	hugo new posts/$(shell echo "$(TITLE)" | tr '[:upper:]' '[:lower:]' | tr ' ' '-').md

# Build with production settings (minified, production environment)
deploy:
	@echo "Building for deployment..."
	HUGO_ENVIRONMENT=production HUGO_ENV=production hugo --minify
