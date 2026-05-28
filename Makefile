.PHONY: build test app clean run

build:
	swift build

test:
	swift test

app:
	./scripts/bundle-app.sh

run: build
	swift run winch

clean:
	rm -rf .build
