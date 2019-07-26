all: setup build

build:
	bash ./scripts/pibuilder.sh

	@echo "Now write .${OUT_DIR}/cache/os.img to an SD card and put into a Pi. This will take up to 5 minutes to configure"
.PHONY: build

setup:
	node ./scripts/setup.js

	@echo "Now run 'make build' to configure the image"
.PHONY: setup

test:
	npm test
.PHONY: test

version:
	@echo $(TRAVIS_TAG:v%=%)
.PHONY: version
