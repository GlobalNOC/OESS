Summary: OESS Perl Libraries
Name: perl-OESS
Version: 1.1.8
Release: 1
License: APL 2.0
Group: Network
URL: http://globalnoc.iu.edu
Source0: %{name}-%{version}.tar.gz
BuildRoot: %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
BuildArch:noarch

BuildRequires: perl
Requires: perl(URI::Escape), dbus, dbus-libs, mysql-server, perl-XML-Simple, perl-XML-XPath, perl-Module-Build, perl-Module-Install, perl-Array-Utils, perl-File-ShareDir, perl-Net-DBus, perl-XML-Writer, perl-DateTime, perl-Test-Deep, perl-Set-Scalar, perl-Graph, perl-List-MoreUtils, perl-Log-Log4perl, perl-MIME-Lite-TT-HTML, perl-AnyEvent, perl-AnyEvent-Fork, perl-AnyEvent-Fork-RPC, perl-AnyEvent-DBus, perl-Proc-FastSpawn perl-SOAP-Lite
Provides: perl-OESS-Circuit, perl-OESS-Database, perl-OESS-DBus, perl-OESS-Topology,perl-OESS-Measurement,perl-OESS-FlowRule
Obsoletes: perl-OESS-Circuit, perl-OESS-Database, perl-OESS-DBus, perl-OESS-Topology,perl-OESS-Measurement,perl-OESS-FlowRule

%description

%define docdir /usr/share/doc/%{name}-%{version}/
%define template_dir /usr/share/oess-core/

%prep
%setup -q

%build
%{__perl} Makefile.PL PREFIX="%{buildroot}%{_prefix}" INSTALLDIRS="vendor"
make

%check


%install
rm -rf $RPM_BUILD_ROOT
make pure_install
%__mkdir -p -m 0775 $RPM_BUILD_ROOT%{docdir}/share/upgrade
%__mkdir -p -m 0775 $RPM_BUILD_ROOT%{template_dir}
%__install etc/notification_templates.tmpl $RPM_BUILD_ROOT/%{template_dir}/
%__install etc/notification_bulk.tmpl $RPM_BUILD_ROOT/%{template_dir}/
%__install etc/notification_bulk.tt.html $RPM_BUILD_ROOT/%{template_dir}/
%__install etc/notification.tt.html $RPM_BUILD_ROOT/%{template_dir}/
%__install share/nddi.sql $RPM_BUILD_ROOT/%{docdir}/share/
%__install share/upgrade/* $RPM_BUILD_ROOT/%{docdir}/share/upgrade/
# clean up buildroot
find %{buildroot} -name .packlist -exec %{__rm} {} \;

%{_fixperms} $RPM_BUILD_ROOT/*

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%doc %{_mandir}/man3/OESS::Circuit.3pm.gz
%doc %{_mandir}/man3/OESS::Database.3pm.gz
%doc %{_mandir}/man3/OESS::DBus.3pm.gz
%doc %{_mandir}/man3/OESS::Topology.3pm.gz
%doc %{_mandir}/man3/OESS::Measurement.3pm.gz
%doc %{_mandir}/man3/OESS::FlowRule.3pm.gz
%doc %{_mandir}/man3/OESS::Notification.3pm.gz
%doc %{_mandir}/man3/OESS::Traceroute.3pm.gz
%doc %{_mandir}/man3/OESS::Watchdog.3pm.gz
%doc %{_mandir}/man3/OESS::FWDCTL::Master.3pm.gz
%doc %{_mandir}/man3/OESS::FWDCTL::Switch.3pm.gz
%doc %{_mandir}/man3/OESS::Traceroute.3pm.gz
%doc %{_mandir}/man3/OESS::FV.3pm.gz
%doc %{_mandir}/man3/OESS::NSI::Server.3pm.gz
%doc %{_mandir}/man3/OESS::NSI::Constant.3pm.gz
%doc %{_mandir}/man3/OESS::NSI::Daemon.3pm.gz
%doc %{_mandir}/man3/OESS::NSI::Processor.3pm.gz
%doc %{_mandir}/man3/OESS::NSI::Provisioning.3pm.gz
%doc %{_mandir}/man3/OESS::NSI::Query.3pm.gz
%doc %{_mandir}/man3/OESS::NSI::Reservation.3pm.gz
%doc %{_mandir}/man3/OESS::NSI::Utils.3pm.gz
%{template_dir}/notification_templates.tmpl
%{template_dir}/notification_bulk.tmpl
%{template_dir}/notification_bulk.tt.html
%{template_dir}/notification.tt.html
%{perl_vendorlib}/OESS/Notification.pm
%{perl_vendorlib}/OESS/Traceroute.pm
%{perl_vendorlib}/OESS/DBus.pm
%{perl_vendorlib}/OESS/Database.pm
%{perl_vendorlib}/OESS/Topology.pm
%{perl_vendorlib}/OESS/Measurement.pm
%{perl_vendorlib}/OESS/Circuit.pm
%{perl_vendorlib}/OESS/FlowRule.pm
%{perl_vendorlib}/OESS/FV.pm
%{perl_vendorlib}/OESS/Watchdog.pm
%{perl_vendorlib}/OESS/FWDCTL/Master.pm
%{perl_vendorlib}/OESS/FWDCTL/Switch.pm
%{perl_vendorlib}/OESS/Traceroute.pm
%{perl_vendorlib}/OESS/NSI/Server.pm
%{perl_vendorlib}/OESS/NSI/Constant.pm
%{perl_vendorlib}/OESS/NSI/Daemon.pm
%{perl_vendorlib}/OESS/NSI/Processor.pm
%{perl_vendorlib}/OESS/NSI/Provisioning.pm
%{perl_vendorlib}/OESS/NSI/Query.pm
%{perl_vendorlib}/OESS/NSI/Reservation.pm
%{perl_vendorlib}/OESS/NSI/Utils.pm
%{docdir}/share/nddi.sql
%{docdir}/share/upgrade/*
%changelog
* Thu Dec  5 2013 AJ Ragusa <aragusa@grnoc.iu.edu> - OESS Perl Libs
- Initial build.
