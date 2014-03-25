NAME= oess-core
VERSION = 1.1.3

rpm:	dist
	rpmbuild -ta dist/$(NAME)-$(VERSION).tar.gz

clean:	
	rm -rf dist/$(NAME)-$(VERSION)
	rm -rf dist

dist:
	rm -rf dist/$(NAME)-$($VERSION)
	mkdir -p dist/$(NAME)-$(VERSION)
	cp -r etc/ topo.pl fwdctl.pl oess_scheduler.pl monitoring/ measurement/ notification/ oess_setup.pl snapp.mysql.sql snapp_base.mysql.sql populate_remote_topologies.pl QUICK_START README $(NAME).spec dist/$(NAME)-$(VERSION)/
	cd dist; tar -czvf $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION)/ --exclude .svn
