.PHONY: configure pulumi wireguard

configure:
	./scripts/configure.sh

foundation:
	./scripts/pulumi-up.sh foundation
	./scripts/generate-env.sh
	./scripts/generate-values.sh

wireguard:
	./scripts/wireguard/setup.sh

