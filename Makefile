.PHONY: build app test run inspect format lint

build:
	./scripts/swift-env.sh /usr/bin/xcrun swift build

app:
	./scripts/build-app.sh

test:
	./scripts/swift-env.sh /usr/bin/xcrun swift test

run: app
	open "build/Mouse Light Off.app"

inspect:
	./scripts/swift-env.sh /usr/bin/xcrun swift run MouseLightOff --inspect

format:
	./scripts/swift-env.sh /usr/bin/xcrun swift format format --in-place --recursive Sources Tests Package.swift

lint:
	./scripts/swift-env.sh /usr/bin/xcrun swift format lint --strict --recursive Sources Tests Package.swift
