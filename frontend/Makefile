NAME= oess-frontend
VERSION = 1.1.8

rpm:	dist
	rpmbuild -ta dist/$(NAME)-$(VERSION).tar.gz

clean:	
	rm -rf dist/$(NAME)-$(VERSION)
	rm -rf dist

dist:
	rm -rf dist/$(NAME)-$($VERSION)
	mkdir -p dist/$(NAME)-$(VERSION)
	cp -r Makefile www/ webservice/ conf/ docs/ $(NAME).spec dist/$(NAME)-$(VERSION)/
	cd dist; tar -czvf $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION)/ --exclude .svn --exclude tiles --exclude yui
