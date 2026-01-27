# Makefile for running Ginkgo tests in the binchunk directory

# Default target
all: test
.PHONY: all

# Run tests using Ginkgo
test:
	python scripts/test_build.py
.PHONY: test

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@find . -name "*.o" -type f -delete
	@find . -name "*.a" -type f -delete
	@find . -name "*.test" -type f -delete 
.PHONY: clean 