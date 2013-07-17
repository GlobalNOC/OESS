Summary: OESS Notification Daemon Library
Name: perl-OESS-Notification
Version: 1.0.12
Release: 1
License: APL 2.0
Group: Network
URL: http://globalnoc.iu.edu
Source0: %{name}-%{version}.tar.gz
BuildRoot: %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
BuildArch: noarch

BuildRequires: perl
Requires: perl(URI::Escape),perl(Net::DBus), dbus, dbus-libs, mysql-server
Requires: perl(Template)
Requires: perl(MIME::Lite)
Requires: perl-OESS-Database >= 1.0.12
Requires: perl-OESS-DBus >= 1.0.12

%description

%define docdir /usr/share/oess-core

%prep
%setup -q

%build
%{__perl} Makefile.PL PREFIX="%{buildroot}%{_prefix}" INSTALLDIRS="vendor"
make

%check

      
%install
rm -rf $RPM_BUILD_ROOT
make pure_install
%__mkdir -p -m 0755 $RPM_BUILD_ROOT%{docdir}
%__install etc/notification_templates.tmpl $RPM_BUILD_ROOT/%{docdir}/        
# clean up buildroot
find %{buildroot} -name .packlist -exec %{__rm} {} \;
      
%{_fixperms} $RPM_BUILD_ROOT/*

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%doc %{_mandir}/man3/OESS::Notification.3pm.gz
%{docdir}/notification_templates.tmpl
%{perl_vendorlib}/OESS/Notification.pm


%changelog
* Thu May  9 2013 Grant McNaught <gmcnaugh@gkm.grnoc.iu.edu> - Notification-1
- Initial build.

