Name:		oess-frontend
Version:	1.1.9
Release:	2%{?dist}
Summary:	The core oess service provides

Group:		Network
License:	APL 2.0
URL:		http://www.grnoc.iu.edu	
Source0:	%{name}-%{version}.tar.gz
BuildRoot:	%(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

BuildRequires:	perl
Requires:	perl-OESS >= 1.1.9, perl(Net::DBus),dbus,dbus-libs,mysql-server,oess-core
Requires:       nox >= 0.10.9
Requires:       yui2
Requires:       httpd, mod_ssl
Requires:       nddi-tiles
Requires:	perl-Crypt-SSLeay
Requires:	xmlsec1
Requires:	xmlsec1-openssl
BuildArch:	noarch
%description


%define destdir %{_datadir}/%{name}/
%define subdirs www webservice conf docs

%prep
%setup -q


%build


%install
rm -rf $RPM_BUILD_ROOT

%{__mkdir} -p -m 0755 %{buildroot}/%{_datadir}/%{name}/
%{__mkdir} -p -m 0755 %{buildroot}/etc/httpd/conf.d/

chmod 755 %{subdirs}
cp -ar %{subdirs} %{buildroot}%{destdir}/

%{__install} conf/oe-ss.conf.example %{buildroot}/etc/httpd/conf.d/oe-ss.conf


%clean
rm -rf $RPM_BUILD_ROOT


%files

/%{destdir}
%config(noreplace) /etc/httpd/conf.d/oe-ss.conf
%doc /%{destdir}/docs

%post
mkdir -p %{_sysconfdir}/oess/
mkdir -p /var/run/oess/
chmod a+rw /var/run/oess/

%changelog

