OESS_VERSION=2.0.11
OESS_NETWORK=oess

container:
	docker build -f Dockerfile.dev --tag oess:${OESS_VERSION} .
dev:
	docker run -it \
	--env-file .env \
	--publish 8000:80 \
	--publish 5672:5672 \
	--network ${OESS_NETWORK} \
	--mount type=bind,src=${PWD}/perl-lib/OESS/lib/OESS,dst=/usr/share/perl5/vendor_perl/OESS \
	--mount type=bind,src=${PWD}/frontend,dst=/usr/share/oess-frontend \
	--mount type=bind,src=${PWD}/perl-lib/OESS/share,dst=/usr/share/doc/perl-OESS-${OESS_VERSION}/share \
	oess:${OESS_VERSION} /bin/bash
