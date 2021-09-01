Name:		oess-frontend
Version:	2.0.12
Release:	1%{?dist}
Summary:	The OESS webservices and user interface

Group:		Network
License:	APL 2.0
URL:		http://www.grnoc.iu.edu	
Source0:	%{name}-%{version}.tar.gz
BuildRoot:	%(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

BuildRequires: perl
BuildRequires: python >= 2.6, python-libs >= 2.6
BuildRequires: python-simplejson

Requires: oess-core >= 2.0.12
Requires: yui
Requires: httpd, mod_ssl
Requires: nddi-tiles
Requires: perl-Crypt-SSLeay
Requires: xmlsec1, xmlsec1-openssl

Requires: perl-OESS >= 2.0.12

Requires: perl(strict), perl(warnings)
Requires: perl(AnyEvent)
Requires: perl(CGI)
Requires: perl(Data::Dumper)
Requires: perl(FindBin)
Requires: perl(GRNOC::Config)
Requires: perl(GRNOC::RabbitMQ)                    >= 1.1.1
Requires: perl(GRNOC::RabbitMQ::Client)
Requires: perl(GRNOC::RabbitMQ::Dispatcher)
Requires: perl(GRNOC::WebService)                  >= 1.2.9
Requires: perl(GRNOC::WebService::Dispatcher)
Requires: perl(GRNOC::WebService::Method)
Requires: perl(GRNOC::WebService::Regex)
Requires: perl(HTTP::Headers), perl(HTTP::Request)
Requires: perl(JSON)
Requires: perl(JSON::XS)
Requires: perl(Log::Log4perl)
Requires: perl(LWP::UserAgent)
Requires: perl(MIME::Lite)
Requires: perl(SOAP::Constants), perl(SOAP::Lite), perl(SOAP::Server), perl(SOAP::Trace)
Requires: perl(SOAP::Transport::HTTP), perl(SOAP::Transport::HTTP::CGI)
Requires: perl(Switch)
Requires: perl(Template)
Requires: perl(Time::HiRes)
Requires: perl(URI::Escape)
Requires: perl(XML::Simple), perl(XML::XPath)
Requires: perl-Paws

BuildArch:	noarch

%description


%define destdir %{_datadir}/%{name}/
%define subdirs webservice conf docs www/admin www/css www/html_templates www/js www/js_templates www/js_utilities www/media www/openlayers www/vendor

%prep
rm -rf %{_builddir}

%{__mkdir} -p -m 0755 %{_builddir}%{_datadir}/%{name}/new/admin
cp -ar %{_sourcedir}/%{name}-%{version}/www/new/admin_new/* %{_builddir}%{_datadir}/%{name}/new/admin


%setup -q


%build
cd %{_builddir}%{_datadir}/%{name}/new/admin
npm install
npm run build


%install
rm -rf $RPM_BUILD_ROOT

%{__mkdir} -p -m 0755 %{buildroot}/%{_datadir}/%{name}/
%{__mkdir} -p -m 0755 %{buildroot}/%{_datadir}/%{name}/new
%{__mkdir} -p -m 0755 %{buildroot}/%{_datadir}/%{name}/new/admin
%{__mkdir} -p -m 0755 %{buildroot}/etc/httpd/conf.d/

chmod 755 %{subdirs}
cp -ar %{subdirs} %{buildroot}%{destdir}/

cp www/new/index.cgi %{buildroot}%{destdir}/new
cp -ar %{_builddir}%{_datadir}/%{name}/new/admin/dist/* %{buildroot}/%{_datadir}/%{name}/new/admin

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

