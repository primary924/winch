.PHONY: build test app dmg clean run

build:
	swift build

test:
	swift test

app:
	./scripts/bundle-app.sh

dmg: app
	./scripts/make-dmg.sh

run: build
	swift run winch

clean:
	rm -rf .build
