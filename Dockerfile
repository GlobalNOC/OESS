FROM centos:7
COPY globalnoc-public-el7.repo /etc/yum.repos.d/globalnoc-public-el7.repo
COPY perl-lib/OESS/entrypoint.sh /
RUN yum makecache
RUN yum -y install epel-release
RUN yum -y install perl mariadb-server
RUN yum -y install perl-Carp-Always perl-Test-Deep perl-Test-Exception perl-Test-Pod perl-Test-Pod-Coverage perl-Devel-Cover perl-AnyEvent-HTTP
RUN yum -y install perl-OESS oess-core oess-frontend
RUN chmod 777 /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
