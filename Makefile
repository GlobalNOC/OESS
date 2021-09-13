OESS_VERSION=2.0.12
OESS_NETWORK=oess

container:
	docker build -f Dockerfile.dev --tag oess:${OESS_VERSION} .

# To attach OESS to an existing docker network:
# --network ${OESS_NETWORK}
#
# Allow container to attach to host port via host.docker.internal hostname:
# --add-host=host.docker.internal:host-gateway
dev:
	docker run -it \
	--env-file .env \
	--publish 8000:80 \
	--publish 5672:5672 \
	--add-host=host.docker.internal:host-gateway \
	--mount type=bind,src=${PWD}/perl-lib/OESS/lib/OESS,dst=/usr/share/perl5/vendor_perl/OESS \
	--mount type=bind,src=${PWD}/frontend,dst=/usr/share/oess-frontend \
	--mount type=bind,src=${PWD}/perl-lib/OESS/share,dst=/usr/share/doc/perl-OESS-${OESS_VERSION}/share \
	oess:${OESS_VERSION} /bin/bash

documentation:
	perl docs/generate-webservice-docs.pl
