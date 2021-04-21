
include .env.development

build:

	htpasswd -b -c  frontend/.htpasswd admin "${OESS_ADMIN_PASS}"
	docker build . -f frontend/Dockerfile -t oess-frontend
	docker build . -f app/mpls/Dockerfile.discovery -t oess-netconf-discovery
	docker build . -f app/mpls/Dockerfile.fwdctl -t oess-netconf-fwdctl

start:
	docker stack deploy oess-dev --compose-file docker-compose.development.yml

stop:
	docker stack rm oess-dev

TEST_FILES=

test:
	docker build . -f Dockerfile -t oess-test
	docker run -it -e OESS_TEST_FILES="$(TEST_FILES)" --volume ${PWD}/perl-lib/OESS:/OESS oess-test
