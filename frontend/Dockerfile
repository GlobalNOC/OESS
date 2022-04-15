FROM centos/httpd-24-centos7

USER 0

COPY globalnoc-public-el7.repo /etc/yum.repos.d/globalnoc-public-el7.repo

RUN yum makecache
RUN yum -y install epel-release

RUN yum -y install perl-Carp-Always perl-Test-Deep perl-Test-Exception perl-Test-Pod perl-Test-Pod-Coverage perl-Devel-Cover nddi-tiles httpd-tools perl-Array-Utils perl-Carp-Always perl-Data-Dumper perl-Devel-Cover perl-DBI perl-DBD-mysql perl-File-Path perl-GRNOC-Config perl-Log-Log4perl perl-Net-DBus perl-Pod-Coverage perl-Test-Exception perl-Test-Deep perl-Test-Harness perl-Test-Simple perl-Test-Pod perl-Test-Pod-Coverage perl-Time-HiRes perl-XML-Simple perl-SOAP-Lite perl-NetAddr-IP perl-AnyEvent perl-AnyEvent-Fork perl-Array-Utils perl-Class-Accessor perl-Data-UUID perl-DateTime perl-Exporter perl-File-ShareDir perl-Getopt-Long perl-GRNOC-Config perl-GRNOC-Log perl-GRNOC-RabbitMQ perl-JSON perl-JSON-WebToken perl-JSON-XS perl-List-Compare perl-List-MoreUtils perl-Net-DBus perl-Net-Netconf perl-Proc-Daemon perl-Proc-ProcessTable perl-Set-Scalar perl-Socket perl-Storable perl-Switch perl-Sys-Syslog perl-Template-Toolkit perl-URI perl-XML-Simple perl-XML-Writer perl-SOAP-Lite perl-MIME-Lite-TT-HTML perl-Graph yui2 perl-Paws perl-XML-LibXML perl-GRNOC-WebService perl-Text-CSV perl-Net-IP
RUN yum -y install perl-GRNOC-WebService-Client
# RUN yum -y install grnoc-routerproxy

COPY docker/oess.conf       /etc/httpd/conf.d/oess.conf
COPY frontend               /usr/share/oess-frontend
COPY perl-lib/OESS/lib/OESS /usr/share/perl5/vendor_perl/OESS
COPY docker/logging.conf    /etc/oess/logging.conf
COPY docker/database.xml    /etc/oess/database.xml

RUN touch /var/log/oess.log
RUN chmod 664 /var/log/oess.log
RUN chown default:root /var/log/oess.log

USER 1001

# TODO Make ENTRYPOINT
CMD run-httpd
