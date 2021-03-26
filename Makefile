
build:
	docker build . -f frontend/Dockerfile -t oess-frontend
	docker build . -f app/mpls/Dockerfile.discovery -t oess-netconf-discovery
	docker build . -f app/mpls/Dockerfile.fwdctl -t oess-netconf-fwdctl

start:
	docker stack deploy oess-dev --compose-file docker-compose.development.yml

stop:
	docker stack rm oess-dev
