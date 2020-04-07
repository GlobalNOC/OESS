#!/bin/bash
cd /

cp t/conf/database.xml /etc/oess/database.xml
cp t/conf/passwd.xml /etc/oess/.passwd.xml

/usr/bin/mysql_install_db --user=mysql --ldata=/var/lib/mysql --force
/usr/bin/mysqld_safe --datadir='/var/lib/mysql' &
sleep 3

/usr/bin/mysqladmin -u root password test

perl Makefile.PL
make
make test
