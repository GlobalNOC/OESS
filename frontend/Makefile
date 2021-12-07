NAME= oess-frontend
VERSION = 2.0.14

rpm:	dist
	rpmbuild -ta dist/$(NAME)-$(VERSION).tar.gz

clean:	
	rm -rf dist/$(NAME)-$(VERSION)
	rm -rf dist

dist:
	rm -rf dist/$(NAME)-$($VERSION)
	mkdir -p dist/$(NAME)-$(VERSION)
	cp -r Makefile www/ webservice/ conf/ docs/ $(NAME).spec dist/$(NAME)-$(VERSION)/
	rm -rf dist/$(NAME)-$(VERSION)/www/openlayers/*
	cp -r www/openlayers/{OpenLayers.js,img,theme} dist/$(NAME)-$(VERSION)/www/openlayers/
	cd dist; tar -czvf $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION)/ --exclude .svn --exclude tiles --exclude yui
