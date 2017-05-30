Name:		oess-frontend
Version:	1.2.0
Release:	0.dev01%{?dist}
Summary:	The OESS webservices and user interface

Group:		Network
License:	APL 2.0
URL:		http://www.grnoc.iu.edu	
Source0:	%{name}-%{version}.tar.gz
BuildRoot:	%(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

BuildRequires: perl
BuildRequires: python >= 2.6, python-libs >= 2.6
BuildRequires: python-simplejson

Requires: oess-core >= 1.2.0, nox >= 0.10.10
Requires: yui2
Requires: httpd, mod_ssl
Requires: nddi-tiles
Requires: perl-Crypt-SSLeay
Requires: xmlsec1, xmlsec1-openssl

Requires: perl-OESS >= 1.2.0, perl-OSCARS-Client >= 1.2.0

Requires: perl(strict), perl(warnings)
Requires: perl(AnyEvent)
Requires: perl(CGI)
Requires: perl(Data::Dumper)
Requires: perl(FindBin)
Requires: perl(GRNOC::Config)
Requires: perl(GRNOC::WebService), perl(GRNOC::WebService::Dispatcher), perl(GRNOC::WebService::Method), perl(GRNOC::WebService::Regex)
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

