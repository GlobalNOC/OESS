Name:		oess-core		
Version:	1.1.8
Release:	1%{?dist}
Summary:	The core oess service provides

Group:		Network
License:	APL 2.0
URL:		http://www.grnoc.iu.edu	
Source0:	%{name}-%{version}.tar.gz
BuildRoot:	%(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

BuildRequires:	perl
Requires:       perl(Net::DBus), dbus, dbus-libs, mysql-server
Requires:       nox >= 0.10.8
Requires:		xmlsec1-devel
Requires:		xmlsec1-openssl-devel
Requires(interp): /bin/sh
Requires(rpmlib): rpmlib(CompressedFileNames) <= 3.0.4-1 rpmlib(PayloadFilesHavePrefix) <= 4.0-1
Requires(post): /bin/sh
Requires: /bin/bash /usr/bin/perl perl(CGI) perl(DBI) perl(Data::Dumper) perl(English) perl(FindBin) perl(Getopt::Long) perl(Getopt::Std) perl(HTML::Entities) perl(LockFile::Simple) perl(Net::DBus) perl(Net::DBus::Exporter) perl(Proc::Daemon) perl(RRDs) perl(Socket) perl(Switch) perl(Sys::Hostname) perl(Sys::Syslog) perl(URI::Escape) perl(XML::Simple) perl(XML::Writer) perl(XML::XPath) perl(base) perl(constant) perl(strict) perl(warnings) perl(Term::ReadKey) perl(CPAN)
Requires: perl-OESS >= 1.1.8
BuildArch: noarch
AutoreqProv: no
%description


%define idcdir %{_datadir}/%{name}/idc/
%define docdir /usr/share/%{name}

%prep
%setup -q


%build


%install
rm -rf $RPM_BUILD_ROOT


%__mkdir -p -m 0755 $RPM_BUILD_ROOT%{_bindir}/
%__mkdir -p -m 0755 $RPM_BUILD_ROOT%{idcdir}/OSCARS/
%__mkdir -p -m 0755 $RPM_BUILD_ROOT%{docdir}
%__mkdir -p -m 0755 $RPM_BUILD_ROOT%{_sysconfdir}/oess/

%{__install} oess_setup.pl %{buildroot}/%{_bindir}
%{__install} topo.pl %{buildroot}/%{_bindir}
%{__install} fwdctl.pl %{buildroot}/%{_bindir}
%{__install} oess-fvd.pl %{buildroot}/%{_bindir}
%{__install} oess-traceroute.pl %{buildroot}/%{_bindir}
%{__install} oess-watchdog.pl %{buildroot}/%{_bindir}
%{__install} oess_scheduler.pl %{buildroot}/%{_bindir}
%{__install} oess-nsi %{buildroot}/%{_bindir}
%{__install} measurement/* %{buildroot}/%{_bindir}
%{__install} notification/* %{buildroot}/%{_bindir}
%{__install} populate_remote_topologies.pl %{buildroot}/%{_bindir}

%__mkdir -p -m 0755 $RPM_BUILD_ROOT%{_sysconfdir}/dbus-1/system.d/
%__mkdir -p -m 0755 $RPM_BUILD_ROOT%{_sysconfdir}/init.d/
%__mkdir -p -m 0755 $RPM_BUILD_ROOT/etc/cron.d/

%{__install} etc/logging.conf $RPM_BUILD_ROOT%{_sysconfdir}/oess/
%{__install} etc/watchdog.conf $RPM_BUILD_ROOT%{_sysconfdir}/oess/
%{__install} etc/nddi-dbus.conf $RPM_BUILD_ROOT%{_sysconfdir}/dbus-1/system.d/
%{__install} etc/nsi.conf.example $RPM_BUILD_ROOT%{_sysconfdir}/oess/nsi.conf
%{__install} etc/fwdctl-init-rh  $RPM_BUILD_ROOT%{_sysconfdir}/init.d/oess-fwdctl
%{__install} etc/fvd-init-rh  $RPM_BUILD_ROOT%{_sysconfdir}/init.d/oess-fvd
%{__install} etc/watchdog-init-rh $RPM_BUILD_ROOT%{_sysconfdir}/init.d/oess-watchdog
%{__install} etc/topo-init-rh  $RPM_BUILD_ROOT%{_sysconfdir}/init.d/oess-topo
%{__install} etc/notification-init-rh $RPM_BUILD_ROOT%{_sysconfdir}/init.d/oess-notification
%{__install} etc/traceroute-init-rh $RPM_BUILD_ROOT%{_sysconfdir}/init.d/oess-traceroute
%{__install} etc/vlan_stats-init $RPM_BUILD_ROOT%{_sysconfdir}/init.d/oess-vlan_stats
%{__install} etc/nsi-init-rh $RPM_BUILD_ROOT%{_sysconfdir}/init.d/oess-nsi
%{__install} etc/oess-init-rh $RPM_BUILD_ROOT%{_sysconfdir}/init.d/oess
%{__install} etc/nddi-scheduler.cron $RPM_BUILD_ROOT/etc/cron.d/
%{__install} snapp.mysql.sql $RPM_BUILD_ROOT/%{docdir}/
%{__install} snapp_base.mysql.sql $RPM_BUILD_ROOT/%{docdir}/

%{__install} QUICK_START $RPM_BUILD_ROOT/%{docdir}/
%__mkdir -p -m 0755 $RPM_BUILD_ROOT%{_bindir}/oess/

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%{_bindir}/topo.pl
%{_bindir}/fwdctl.pl
%{_bindir}/oess-fvd.pl
%{_bindir}/oess-traceroute.pl
%{_bindir}/oess-notify.pl
%{_bindir}/oess-watchdog.pl
%{_bindir}/vlan_stats_d.pl
%{_bindir}/oess-nsi
%{_bindir}/snapp-config-gen
%{_bindir}/perfSonar_gen
%{_bindir}/oess_setup.pl
%{_bindir}/oess_scheduler.pl
%{_bindir}/populate_remote_topologies.pl

%{_sysconfdir}/dbus-1/system.d/nddi-dbus.conf
%{_sysconfdir}/init.d/oess-fwdctl
%{_sysconfdir}/init.d/oess-topo
%{_sysconfdir}/init.d/oess-vlan_stats
%{_sysconfdir}/init.d/oess-notification
%{_sysconfdir}/init.d/oess-fvd
%{_sysconfdir}/init.d/oess-traceroute
%{_sysconfdir}/init.d/oess
%{_sysconfdir}/init.d/oess-nsi
%{_sysconfdir}/init.d/oess-watchdog
%{docdir}/snapp.mysql.sql
%{docdir}/snapp_base.mysql.sql
%{docdir}/QUICK_START

%config(noreplace) %{_sysconfdir}/oess/nsi.conf
%config(noreplace) /etc/cron.d/nddi-scheduler.cron
%config(noreplace) %{_sysconfdir}/oess/logging.conf
%config(noreplace) %{_sysconfdir}/oess/watchdog.conf
%doc

%post
mkdir -p /var/run/oess/
mkdir -p /var/log/oess/
chmod a+rw /var/log/oess/
chmod a+rw /var/run/oess/
chmod 644 /etc/cron.d/nddi-scheduler.cron

if [[ ! -L "/usr/lib/ocf/resource.d/grnoc/oess" ]]
    then
        if [[ ! -d "/usr/lib/ocf/" ]]
            then 
                mkdir /usr/lib/ocf;
                mkdir /usr/lib/ocf/resource.d;
                mkdir /usr/lib/ocf/resource.d/grnoc;
            fi; 
        if [[ ! -d "/usr/lib/ocf/resource.d" ]]
            then
                mkdir /usr/lib/ocf/resource.d;
                mkdir /usr/lib/ocf/resource.d/grnoc;
            fi; 
        if [[ ! -d "/usr/lib/ocf/resource.d/grnoc" ]]
            then
                mkdir /usr/lib/ocf/resource.d/grnoc
            fi; 

        ln -s /etc/init.d/oess /usr/lib/ocf/resource.d/grnoc/

fi

%changelog

