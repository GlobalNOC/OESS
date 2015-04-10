NAME= oess-frontend
<<<<<<< HEAD
VERSION = 1.1.5b
=======
VERSION = 1.1.6
>>>>>>> 1b91fbcb90fba95628e12bbc17ed3bb9a75b8640

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
