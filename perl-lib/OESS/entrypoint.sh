#!/bin/bash

pwd
ls -la

cp /OESS/t/conf/database.xml /etc/oess/database.xml
cp /OESS/t/conf/passwd.xml /etc/oess/.passwd.xml

rm -rf /usr/share/perl5/vendor_perl/OESS

/usr/bin/mysql_install_db --user=mysql --ldata=/var/lib/mysql --force
/usr/bin/mysqld_safe --datadir='/var/lib/mysql' &
sleep 3

/usr/bin/mysqladmin -u root password test

cd /OESS

if [ -z "$OESS_TEST_FILES" ]; then
    echo "Running all tests:"
    perl Makefile.PL
    make
    cover -test
else
    echo "Running select tests: $OESS_TEST_FILES"
    perl Makefile.PL
    make
    make test TEST_FILES="$OESS_TEST_FILES"
fi
