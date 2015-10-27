NAME= oess-core
VERSION = 1.1.8

rpm:	dist
	rpmbuild -ta dist/$(NAME)-$(VERSION).tar.gz

clean:	
	rm -rf dist/$(NAME)-$(VERSION)
	rm -rf dist

dist:
	rm -rf dist/$(NAME)-$($VERSION)
	mkdir -p dist/$(NAME)-$(VERSION)
	cp -r etc/ topo.pl oess-nsi fwdctl.pl oess-fvd.pl oess-watchdog.pl oess_scheduler.pl oess-traceroute.pl measurement/ notification/ oess_setup.pl snapp.mysql.sql snapp_base.mysql.sql populate_remote_topologies.pl QUICK_START $(NAME).spec dist/$(NAME)-$(VERSION)/
	cd dist; tar -czvf $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION)/ --exclude .svn
