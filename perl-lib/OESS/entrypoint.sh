#!/bin/bash

pwd
ls -la

cp perl-lib/OESS/t/conf/database.xml /etc/oess/database.xml
cp perl-lib/OESS/t/conf/passwd.xml /etc/oess/.passwd.xml

rm -rf /usr/share/perl5/vendor_perl/OESS

/usr/bin/mysql_install_db --user=mysql --ldata=/var/lib/mysql --force
/usr/bin/mysqld_safe --datadir='/var/lib/mysql' &
sleep 3

/usr/bin/mysqladmin -u root password test


cd perl-lib/OESS
perl Makefile.PL
make
cover -test
