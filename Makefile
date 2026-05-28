.PHONY: build test app dmg icon clean run

build:
	swift build

test:
	swift test

app:
	./scripts/bundle-app.sh

dmg: app
	./scripts/make-dmg.sh

icon:
	./scripts/build-app-icon.sh

run: build
	swift run winch

clean:
	rm -rf .build
