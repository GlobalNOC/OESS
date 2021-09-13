OESS_VERSION=2.0.11
OESS_NETWORK=oess
TEST_FILES=

include .env

build:
	htpasswd -b -c  frontend/.htpasswd admin "${OESS_PASS}"
	docker build . -f frontend/Dockerfile -t oess-frontend
	docker build . -f app/mpls/Dockerfile.discovery -t oess-netconf-discovery
	docker build . -f app/mpls/Dockerfile.fwdctl -t oess-netconf-fwdctl

start:
	docker stack deploy oess-dev --compose-file docker-compose.development.yml

stop:
	docker stack rm oess-dev

test:
	docker build . -f Dockerfile -t oess-test
	docker run -it -e OESS_TEST_FILES="$(TEST_FILES)" --volume ${PWD}/perl-lib/OESS:/OESS oess-test

# For single container builds. Should only be used for testing.
container:
	docker build -f Dockerfile.dev --tag oess:${OESS_VERSION} .

# For single container builds. Should only be used for testing.
# NET_RAW and NET_ADMIN allow for low level debugging using packet capture
dev:
	docker run -it \
	--env-file .env \
	--publish 8000:80 \
	--publish 5672:5672 \
	--network ${OESS_NETWORK} \
	--mount type=bind,src=${PWD}/perl-lib/OESS/lib/OESS,dst=/usr/share/perl5/vendor_perl/OESS \
	--mount type=bind,src=${PWD}/frontend,dst=/usr/share/oess-frontend \
	--mount type=bind,src=${PWD}/perl-lib/OESS/share,dst=/usr/share/doc/perl-OESS-${OESS_VERSION}/share \
	--cap-add=NET_RAW \
	--cap-add=NET_ADMIN \
	oess:${OESS_VERSION} /bin/bash

documentation:
	perl docs/generate-webservice-docs.pl
