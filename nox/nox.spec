Name:	nox		
Version: 0.10.8
Release: 1%{?dist}
Summary: nox an openflow controller	

Group:	Networking	
License: GPLv3	
URL:	http://www.noxrepo.org	
Source0: nox.tar.gz	
#BuildRoot:	%(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root

BuildRequires:	gcc, gcc-c++,boost,dbus,boost-filesystem,boost-test,openssl-devel,boost-devel,python-devel
Requires: dbus-python, python,openssl,swig,python,python-twisted,pygobject2

%description
The dbus enhanced openflow conrtoller

%prep
%setup -q -n nox


%build
#mkdir build/
#cd build/
#../configure --with-boost-filesystem=boost_filesystem --with-boost-unit-test-framework=boost_unit_test_framework
%configure --with-boost-filesystem=boost_filesystem --with-boost-unit-test-framework=boost_unit_test_framework
#
#cd build/
make %{?_smp_mflags} -j 2


%install
rm -rf %{buildroot}
#rm -rf $RPM_BUILD_ROOT
#cd build/
#make install DESTDIR=$RPM_BUILD_ROOT
make install DESTDIR=%{buildroot}

%__mkdir -p -m 0755 $RPM_BUILD_ROOT/etc/init.d/
%__mkdir -p -m 0755 $RPM_BUILD_ROOT/etc/sysconfig/
#%__install -p -m 0644 src/nox.info $RPM_BUILD_ROOT/var/lib/nox


%{__install} -Dp -m0755 init/nox_cored                 %{buildroot}/etc/init.d/
%{__install} -Dp -m0755 init/sysconfig/nox_cored        %{buildroot}/etc/sysconfig/



%clean
rm -rf $RPM_BUILD_ROOT
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
#%{_sbindir}/nox_core
#   /var/lib/nox/nox.info
   /etc/init.d/nox_cored
%config(noreplace)   /etc/sysconfig/nox_cored
   /etc/nox/nox.json
   /etc/nox/noxca.cert
   /etc/nox/noxca.key.insecure
   /usr/bin/builtin/libbuiltin.la
   /usr/bin/builtin/libbuiltin.so
   /usr/bin/builtin/libbuiltin.so.0
   /usr/bin/builtin/libbuiltin.so.0.0.0
   /usr/bin/gen-nox-cert.sh
   /usr/bin/nox-monitor
   /usr/bin/nox/__init__.pyc
   /usr/bin/nox/coreapps/__init__.pyc
   /usr/bin/nox/coreapps/coretests/TEST_DIRECTORY
   /usr/bin/nox/coreapps/coretests/__init__.pyc
   /usr/bin/nox/coreapps/coretests/async_test.la
   /usr/bin/nox/coreapps/coretests/async_test.so
   /usr/bin/nox/coreapps/coretests/async_test.so.0
   /usr/bin/nox/coreapps/coretests/async_test.so.0.0.0
   /usr/bin/nox/coreapps/coretests/cacert.pem
   /usr/bin/nox/coreapps/coretests/meta.json
   /usr/bin/nox/coreapps/coretests/servercert.pem
   /usr/bin/nox/coreapps/coretests/serverkey.pem
   /usr/bin/nox/coreapps/coretests/ssl_test.la
   /usr/bin/nox/coreapps/coretests/ssl_test.so
   /usr/bin/nox/coreapps/coretests/ssl_test.so.0
   /usr/bin/nox/coreapps/coretests/ssl_test.so.0.0.0
   /usr/bin/nox/coreapps/coretests/test_async.sh
   /usr/bin/nox/coreapps/coretests/test_basic_callback.pyc
   /usr/bin/nox/coreapps/coretests/test_basic_callback.sh
   /usr/bin/nox/coreapps/coretests/test_mod.pyc
   /usr/bin/nox/coreapps/coretests/test_packet.pyc
   /usr/bin/nox/coreapps/coretests/test_packet.sh
   /usr/bin/nox/coreapps/coretests/test_ssl.sh
   /usr/bin/nox/coreapps/examples/__init__.pyc
   /usr/bin/nox/coreapps/examples/countdown.pyc
   /usr/bin/nox/coreapps/examples/dnsspy.pyc
   /usr/bin/nox/coreapps/examples/meta.json
   /usr/bin/nox/coreapps/examples/monitor.pyc
   /usr/bin/nox/coreapps/examples/packetdump.pyc
   /usr/bin/nox/coreapps/examples/pyloop.pyc
   /usr/bin/nox/coreapps/examples/pyswitch.pyc
   /usr/bin/nox/coreapps/examples/t/TEST_DIRECTORY
   /usr/bin/nox/coreapps/examples/t/__init__.pyc
   /usr/bin/nox/coreapps/examples/t/meta.json
   /usr/bin/nox/coreapps/examples/t/test_example.pyc
   /usr/bin/nox/coreapps/examples/t/test_example.sh
   /usr/bin/nox/coreapps/hub/hub.la
   /usr/bin/nox/coreapps/hub/hub.so
   /usr/bin/nox/coreapps/hub/hub.so.0
   /usr/bin/nox/coreapps/hub/hub.so.0.0.0
   /usr/bin/nox/coreapps/hub/meta.json
   /usr/bin/nox/coreapps/messenger/__init__.pyc
   /usr/bin/nox/coreapps/messenger/_pyjsonmsgevent.la
   /usr/bin/nox/coreapps/messenger/_pyjsonmsgevent.so
   /usr/bin/nox/coreapps/messenger/_pyjsonmsgevent.so.0
   /usr/bin/nox/coreapps/messenger/_pyjsonmsgevent.so.0.0.0
   /usr/bin/nox/coreapps/messenger/cacert.pem
   /usr/bin/nox/coreapps/messenger/jsonmessenger.la
   /usr/bin/nox/coreapps/messenger/jsonmessenger.so
   /usr/bin/nox/coreapps/messenger/jsonmessenger.so.0
   /usr/bin/nox/coreapps/messenger/jsonmessenger.so.0.0.0
   /usr/bin/nox/coreapps/messenger/jsonmsg_event.la
   /usr/bin/nox/coreapps/messenger/jsonmsg_event.so
   /usr/bin/nox/coreapps/messenger/jsonmsg_event.so.0
   /usr/bin/nox/coreapps/messenger/jsonmsg_event.so.0.0.0
   /usr/bin/nox/coreapps/messenger/messenger.la
   /usr/bin/nox/coreapps/messenger/messenger.pyc
   /usr/bin/nox/coreapps/messenger/messenger.so
   /usr/bin/nox/coreapps/messenger/messenger.so.0
   /usr/bin/nox/coreapps/messenger/messenger.so.0.0.0
   /usr/bin/nox/coreapps/messenger/messenger_core.la
   /usr/bin/nox/coreapps/messenger/messenger_core.so
   /usr/bin/nox/coreapps/messenger/messenger_core.so.0
   /usr/bin/nox/coreapps/messenger/messenger_core.so.0.0.0
   /usr/bin/nox/coreapps/messenger/meta.json
   /usr/bin/nox/coreapps/messenger/pyjsonmsgevent.pyc
   /usr/bin/nox/coreapps/messenger/pyjsonmsgevent_wrap.cc
   /usr/bin/nox/coreapps/messenger/servercert.pem
   /usr/bin/nox/coreapps/messenger/serverkey.pem
   /usr/bin/nox/coreapps/pyrt/__init__.pyc
   /usr/bin/nox/coreapps/pyrt/_deferredcallback.la
   /usr/bin/nox/coreapps/pyrt/_deferredcallback.so
   /usr/bin/nox/coreapps/pyrt/_deferredcallback.so.0
   /usr/bin/nox/coreapps/pyrt/_deferredcallback.so.0.0.0
   /usr/bin/nox/coreapps/pyrt/_oxidereactor.la
   /usr/bin/nox/coreapps/pyrt/_oxidereactor.so
   /usr/bin/nox/coreapps/pyrt/_oxidereactor.so.0
   /usr/bin/nox/coreapps/pyrt/_oxidereactor.so.0.0.0
   /usr/bin/nox/coreapps/pyrt/_pycomponent.la
   /usr/bin/nox/coreapps/pyrt/_pycomponent.so
   /usr/bin/nox/coreapps/pyrt/_pycomponent.so.0
   /usr/bin/nox/coreapps/pyrt/_pycomponent.so.0.0.0
   /usr/bin/nox/coreapps/pyrt/bootstrap.pyc
   /usr/bin/nox/coreapps/pyrt/componentws.pyc
   /usr/bin/nox/coreapps/pyrt/deferredcallback.pyc
   /usr/bin/nox/coreapps/pyrt/meta.json
   /usr/bin/nox/coreapps/pyrt/oxidereactor.pyc
   /usr/bin/nox/coreapps/pyrt/pycomponent.pyc
   /usr/bin/nox/coreapps/pyrt/pyoxidereactor.pyc
   /usr/bin/nox/coreapps/pyrt/pyrt.la
   /usr/bin/nox/coreapps/pyrt/pyrt.so
   /usr/bin/nox/coreapps/pyrt/pyrt.so.0
   /usr/bin/nox/coreapps/pyrt/pyrt.so.0.0.0
   /usr/bin/nox/coreapps/simple_c_app/meta.json
   /usr/bin/nox/coreapps/simple_c_app/simple_cc_app.la
   /usr/bin/nox/coreapps/simple_c_app/simple_cc_app.so
   /usr/bin/nox/coreapps/simple_c_app/simple_cc_app.so.0
   /usr/bin/nox/coreapps/simple_c_app/simple_cc_app.so.0.0.0
   /usr/bin/nox/coreapps/simple_c_py_app/__init__.pyc
   /usr/bin/nox/coreapps/simple_c_py_app/_pysimple_cc_py_app.la
   /usr/bin/nox/coreapps/simple_c_py_app/_pysimple_cc_py_app.so
   /usr/bin/nox/coreapps/simple_c_py_app/_pysimple_cc_py_app.so.0
   /usr/bin/nox/coreapps/simple_c_py_app/_pysimple_cc_py_app.so.0.0.0
   /usr/bin/nox/coreapps/simple_c_py_app/meta.json
   /usr/bin/nox/coreapps/simple_c_py_app/simple_cc_py_app.la
   /usr/bin/nox/coreapps/simple_c_py_app/simple_cc_py_app.so
   /usr/bin/nox/coreapps/simple_c_py_app/simple_cc_py_app.so.0
   /usr/bin/nox/coreapps/simple_c_py_app/simple_cc_py_app.so.0.0.0
   /usr/bin/nox/coreapps/simple_py_app/__init__.pyc
   /usr/bin/nox/coreapps/simple_py_app/meta.json
   /usr/bin/nox/coreapps/simple_py_app/simple_app.pyc
   /usr/bin/nox/coreapps/snmp/meta.json
   /usr/bin/nox/coreapps/snmp/snmp.la
   /usr/bin/nox/coreapps/snmp/snmp.so
   /usr/bin/nox/coreapps/snmp/snmp.so.0
   /usr/bin/nox/coreapps/snmp/snmp.so.0.0.0
   /usr/bin/nox/coreapps/switch/meta.json
   /usr/bin/nox/coreapps/switch/switch.la
   /usr/bin/nox/coreapps/switch/switch.so
   /usr/bin/nox/coreapps/switch/switch.so.0
   /usr/bin/nox/coreapps/switch/switch.so.0.0.0
   /usr/bin/nox/coreapps/testharness/__init__.pyc
   /usr/bin/nox/coreapps/testharness/initindicator.pyc
   /usr/bin/nox/coreapps/testharness/meta.json
   /usr/bin/nox/coreapps/testharness/testdefs.pyc
   /usr/bin/nox/coreapps/testharness/testdefs.sh
   /usr/bin/nox/coreapps/testharness/testharness.pyc
   /usr/bin/nox/coreapps/testharness/testrunner.pyc
   /usr/bin/nox/lib/__init__.pyc
   /usr/bin/nox/lib/_config.la
   /usr/bin/nox/lib/_config.so
   /usr/bin/nox/lib/_config.so.0
   /usr/bin/nox/lib/_config.so.0.0.0
   /usr/bin/nox/lib/_openflow.la
   /usr/bin/nox/lib/_openflow.so
   /usr/bin/nox/lib/_openflow.so.0
   /usr/bin/nox/lib/_openflow.so.0.0.0
   /usr/bin/nox/lib/config.pyc
   /usr/bin/nox/lib/core.pyc
   /usr/bin/nox/lib/directory.pyc
   /usr/bin/nox/lib/directory_factory.pyc
   /usr/bin/nox/lib/netinet/__init__.pyc
   /usr/bin/nox/lib/netinet/_netinet.la
   /usr/bin/nox/lib/netinet/_netinet.so
   /usr/bin/nox/lib/netinet/_netinet.so.0
   /usr/bin/nox/lib/netinet/_netinet.so.0.0.0
   /usr/bin/nox/lib/netinet/netinet.pyc
   /usr/bin/nox/lib/openflow.pyc
   /usr/bin/nox/lib/packet/__init__.pyc
   /usr/bin/nox/lib/packet/arp.pyc
   /usr/bin/nox/lib/packet/bpdu.pyc
   /usr/bin/nox/lib/packet/dhcp.pyc
   /usr/bin/nox/lib/packet/dns.pyc
   /usr/bin/nox/lib/packet/eap.pyc
   /usr/bin/nox/lib/packet/eapol.pyc
   /usr/bin/nox/lib/packet/ethernet.pyc
   /usr/bin/nox/lib/packet/icmp.pyc
   /usr/bin/nox/lib/packet/ipv4.pyc
   /usr/bin/nox/lib/packet/llc.pyc
   /usr/bin/nox/lib/packet/lldp.pyc
   /usr/bin/nox/lib/packet/oui.txt
   /usr/bin/nox/lib/packet/packet_base.pyc
   /usr/bin/nox/lib/packet/packet_exceptions.pyc
   /usr/bin/nox/lib/packet/packet_utils.pyc
   /usr/bin/nox/lib/packet/t/__init__.pyc
   /usr/bin/nox/lib/packet/t/dhcp_parse_test.pyc
   /usr/bin/nox/lib/packet/t/dns_parse_test.pyc
   /usr/bin/nox/lib/packet/t/eap_parse_test.pyc
   /usr/bin/nox/lib/packet/t/ethernet_parse_test.pyc
   /usr/bin/nox/lib/packet/t/icmp_parse_test.pyc
   /usr/bin/nox/lib/packet/t/ipv4_parse_test.pyc
   /usr/bin/nox/lib/packet/t/lldp_parse_test.pyc
   /usr/bin/nox/lib/packet/t/tcp_parse_test.pyc
   /usr/bin/nox/lib/packet/t/udp_parse_test.pyc
   /usr/bin/nox/lib/packet/t/vlan_parse_test.pyc
   /usr/bin/nox/lib/packet/tcp.pyc
   /usr/bin/nox/lib/packet/udp.pyc
   /usr/bin/nox/lib/packet/vlan.pyc
   /usr/bin/nox/lib/pyopenflow.pyc
   /usr/bin/nox/lib/registries.pyc
   /usr/bin/nox/lib/token_bucket.pyc
   /usr/bin/nox/lib/utf8_string.i
   /usr/bin/nox/lib/util.pyc
   /usr/bin/nox/netapps/__init__.pyc
   /usr/bin/nox/netapps/authenticator/__init__.pyc
   /usr/bin/nox/netapps/authenticator/_pyauth.la
   /usr/bin/nox/netapps/authenticator/_pyauth.so
   /usr/bin/nox/netapps/authenticator/_pyauth.so.0
   /usr/bin/nox/netapps/authenticator/_pyauth.so.0.0.0
   /usr/bin/nox/netapps/authenticator/_pyflowutil.la
   /usr/bin/nox/netapps/authenticator/_pyflowutil.so
   /usr/bin/nox/netapps/authenticator/_pyflowutil.so.0
   /usr/bin/nox/netapps/authenticator/_pyflowutil.so.0.0.0
   /usr/bin/nox/netapps/authenticator/authenticator.la
   /usr/bin/nox/netapps/authenticator/authenticator.so
   /usr/bin/nox/netapps/authenticator/authenticator.so.0
   /usr/bin/nox/netapps/authenticator/authenticator.so.0.0.0
   /usr/bin/nox/netapps/authenticator/flowutil.la
   /usr/bin/nox/netapps/authenticator/flowutil.so
   /usr/bin/nox/netapps/authenticator/flowutil.so.0
   /usr/bin/nox/netapps/authenticator/flowutil.so.0.0.0
   /usr/bin/nox/netapps/authenticator/meta.json
   /usr/bin/nox/netapps/authenticator/pyauth.pyc
   /usr/bin/nox/netapps/authenticator/pyauth_wrap.cc
   /usr/bin/nox/netapps/authenticator/pyflowutil.pyc
   /usr/bin/nox/netapps/authenticator/pyflowutil_wrap.cc
   /usr/bin/nox/netapps/bindings_storage/__init__.pyc
   /usr/bin/nox/netapps/bindings_storage/_pybindings_storage.la
   /usr/bin/nox/netapps/bindings_storage/_pybindings_storage.so
   /usr/bin/nox/netapps/bindings_storage/_pybindings_storage.so.0
   /usr/bin/nox/netapps/bindings_storage/_pybindings_storage.so.0.0.0
   /usr/bin/nox/netapps/bindings_storage/bindings_directory.pyc
   /usr/bin/nox/netapps/bindings_storage/bindings_storage.la
   /usr/bin/nox/netapps/bindings_storage/bindings_storage.so
   /usr/bin/nox/netapps/bindings_storage/bindings_storage.so.0
   /usr/bin/nox/netapps/bindings_storage/bindings_storage.so.0.0.0
   /usr/bin/nox/netapps/bindings_storage/meta.json
   /usr/bin/nox/netapps/bindings_storage/pybindings_storage.pyc
   /usr/bin/nox/netapps/bindings_storage/t/TEST_DIRECTORY
   /usr/bin/nox/netapps/bindings_storage/t/__init__.pyc
   /usr/bin/nox/netapps/bindings_storage/t/meta.json
   /usr/bin/nox/netapps/bindings_storage/t/test_bs_link.pyc
   /usr/bin/nox/netapps/bindings_storage/t/test_bs_link.sh
   /usr/bin/nox/netapps/bindings_storage/t/test_bs_location.pyc
   /usr/bin/nox/netapps/data/__init__.pyc
   /usr/bin/nox/netapps/data/_pydatacache.la
   /usr/bin/nox/netapps/data/_pydatacache.so
   /usr/bin/nox/netapps/data/_pydatacache.so.0
   /usr/bin/nox/netapps/data/_pydatacache.so.0.0.0
   /usr/bin/nox/netapps/data/_pydatatypes.la
   /usr/bin/nox/netapps/data/_pydatatypes.so
   /usr/bin/nox/netapps/data/_pydatatypes.so.0
   /usr/bin/nox/netapps/data/_pydatatypes.so.0.0.0
   /usr/bin/nox/netapps/data/datacache.la
   /usr/bin/nox/netapps/data/datacache.so
   /usr/bin/nox/netapps/data/datacache.so.0
   /usr/bin/nox/netapps/data/datacache.so.0.0.0
   /usr/bin/nox/netapps/data/datacache_impl.pyc
   /usr/bin/nox/netapps/data/datatypes.la
   /usr/bin/nox/netapps/data/datatypes.so
   /usr/bin/nox/netapps/data/datatypes.so.0
   /usr/bin/nox/netapps/data/datatypes.so.0.0.0
   /usr/bin/nox/netapps/data/datatypes_impl.pyc
   /usr/bin/nox/netapps/data/meta.json
   /usr/bin/nox/netapps/data/pydatacache.pyc
   /usr/bin/nox/netapps/data/pydatatypes.pyc
   /usr/bin/nox/netapps/discovery/__init__.pyc
   /usr/bin/nox/netapps/discovery/_pylinkevent.la
   /usr/bin/nox/netapps/discovery/_pylinkevent.so
   /usr/bin/nox/netapps/discovery/_pylinkevent.so.0
   /usr/bin/nox/netapps/discovery/_pylinkevent.so.0.0.0
   /usr/bin/nox/netapps/discovery/discovery.pyc
   /usr/bin/nox/netapps/discovery/discoveryws.pyc
   /usr/bin/nox/netapps/discovery/link_event.la
   /usr/bin/nox/netapps/discovery/link_event.so
   /usr/bin/nox/netapps/discovery/link_event.so.0
   /usr/bin/nox/netapps/discovery/link_event.so.0.0.0
   /usr/bin/nox/netapps/discovery/meta.json
   /usr/bin/nox/netapps/discovery/pylinkevent.pyc
   /usr/bin/nox/netapps/discovery/pylinkevent_wrap.cc
   /usr/bin/nox/netapps/flow_fetcher/__init__.pyc
   /usr/bin/nox/netapps/flow_fetcher/_pyflow_fetcher.la
   /usr/bin/nox/netapps/flow_fetcher/_pyflow_fetcher.so
   /usr/bin/nox/netapps/flow_fetcher/_pyflow_fetcher.so.0
   /usr/bin/nox/netapps/flow_fetcher/_pyflow_fetcher.so.0.0.0
   /usr/bin/nox/netapps/flow_fetcher/flow_fetcher.la
   /usr/bin/nox/netapps/flow_fetcher/flow_fetcher.so
   /usr/bin/nox/netapps/flow_fetcher/flow_fetcher.so.0
   /usr/bin/nox/netapps/flow_fetcher/flow_fetcher.so.0.0.0
   /usr/bin/nox/netapps/flow_fetcher/meta.json
   /usr/bin/nox/netapps/flow_fetcher/pyflow_fetcher.pyc
   /usr/bin/nox/netapps/flow_fetcher/test.pyc
   /usr/bin/nox/netapps/flowtracer/__init__.pyc
   /usr/bin/nox/netapps/flowtracer/flowtracer.pyc
   /usr/bin/nox/netapps/flowtracer/meta.json
   /usr/bin/nox/netapps/hoststate/hostip.la
   /usr/bin/nox/netapps/hoststate/hostip.so
   /usr/bin/nox/netapps/hoststate/hostip.so.0
   /usr/bin/nox/netapps/hoststate/hostip.so.0.0.0
   /usr/bin/nox/netapps/hoststate/hosttracker.la
   /usr/bin/nox/netapps/hoststate/hosttracker.so
   /usr/bin/nox/netapps/hoststate/hosttracker.so.0
   /usr/bin/nox/netapps/hoststate/hosttracker.so.0.0.0
   /usr/bin/nox/netapps/hoststate/meta.json
   /usr/bin/nox/netapps/hoststate/trackhost_pktin.la
   /usr/bin/nox/netapps/hoststate/trackhost_pktin.so
   /usr/bin/nox/netapps/hoststate/trackhost_pktin.so.0
   /usr/bin/nox/netapps/hoststate/trackhost_pktin.so.0.0.0
   /usr/bin/nox/netapps/lavi/lavi.la
   /usr/bin/nox/netapps/lavi/lavi.so
   /usr/bin/nox/netapps/lavi/lavi.so.0
   /usr/bin/nox/netapps/lavi/lavi.so.0.0.0
   /usr/bin/nox/netapps/lavi/lavi_flows.la
   /usr/bin/nox/netapps/lavi/lavi_flows.so
   /usr/bin/nox/netapps/lavi/lavi_flows.so.0
   /usr/bin/nox/netapps/lavi/lavi_flows.so.0.0.0
   /usr/bin/nox/netapps/lavi/lavi_host2sw.la
   /usr/bin/nox/netapps/lavi/lavi_host2sw.so
   /usr/bin/nox/netapps/lavi/lavi_host2sw.so.0
   /usr/bin/nox/netapps/lavi/lavi_host2sw.so.0.0.0
   /usr/bin/nox/netapps/lavi/lavi_hostflow.la
   /usr/bin/nox/netapps/lavi/lavi_hostflow.so
   /usr/bin/nox/netapps/lavi/lavi_hostflow.so.0
   /usr/bin/nox/netapps/lavi/lavi_hostflow.so.0.0.0
   /usr/bin/nox/netapps/lavi/lavi_hosts.la
   /usr/bin/nox/netapps/lavi/lavi_hosts.so
   /usr/bin/nox/netapps/lavi/lavi_hosts.so.0
   /usr/bin/nox/netapps/lavi/lavi_hosts.so.0.0.0
   /usr/bin/nox/netapps/lavi/lavi_links.la
   /usr/bin/nox/netapps/lavi/lavi_links.so
   /usr/bin/nox/netapps/lavi/lavi_links.so.0
   /usr/bin/nox/netapps/lavi/lavi_links.so.0.0.0
   /usr/bin/nox/netapps/lavi/lavi_networkflow.la
   /usr/bin/nox/netapps/lavi/lavi_networkflow.so
   /usr/bin/nox/netapps/lavi/lavi_networkflow.so.0
   /usr/bin/nox/netapps/lavi/lavi_networkflow.so.0.0.0
   /usr/bin/nox/netapps/lavi/lavi_nodes.la
   /usr/bin/nox/netapps/lavi/lavi_nodes.so
   /usr/bin/nox/netapps/lavi/lavi_nodes.so.0
   /usr/bin/nox/netapps/lavi/lavi_nodes.so.0.0.0
   /usr/bin/nox/netapps/lavi/lavi_switches.la
   /usr/bin/nox/netapps/lavi/lavi_switches.so
   /usr/bin/nox/netapps/lavi/lavi_switches.so.0
   /usr/bin/nox/netapps/lavi/lavi_switches.so.0.0.0
   /usr/bin/nox/netapps/lavi/lavi_swlinks.la
   /usr/bin/nox/netapps/lavi/lavi_swlinks.so
   /usr/bin/nox/netapps/lavi/lavi_swlinks.so.0
   /usr/bin/nox/netapps/lavi/lavi_swlinks.so.0.0.0
   /usr/bin/nox/netapps/lavi/lavitest_showflow.la
   /usr/bin/nox/netapps/lavi/lavitest_showflow.so
   /usr/bin/nox/netapps/lavi/lavitest_showflow.so.0
   /usr/bin/nox/netapps/lavi/lavitest_showflow.so.0.0.0
   /usr/bin/nox/netapps/lavi/meta.json
   /usr/bin/nox/netapps/monitoring/__init__.pyc
   /usr/bin/nox/netapps/monitoring/linkadmindownevent.pyc
   /usr/bin/nox/netapps/monitoring/linkadminupevent.pyc
   /usr/bin/nox/netapps/monitoring/linkutilreplyevent.pyc
   /usr/bin/nox/netapps/monitoring/meta.json
   /usr/bin/nox/netapps/monitoring/monitoring.pyc
   /usr/bin/nox/netapps/monitoring/porterrorevent.pyc
   /usr/bin/nox/netapps/monitoring/silentswitchevent.pyc
   /usr/bin/nox/netapps/monitoring/switchadmindownevent.pyc
   /usr/bin/nox/netapps/monitoring/switchadminupevent.pyc
   /usr/bin/nox/netapps/monitoring/switchqueryreplyevent.pyc
   /usr/bin/nox/netapps/networkstate/datapathmem.la
   /usr/bin/nox/netapps/networkstate/datapathmem.so
   /usr/bin/nox/netapps/networkstate/datapathmem.so.0
   /usr/bin/nox/netapps/networkstate/datapathmem.so.0.0.0
   /usr/bin/nox/netapps/networkstate/linkload.la
   /usr/bin/nox/netapps/networkstate/linkload.so
   /usr/bin/nox/netapps/networkstate/linkload.so.0
   /usr/bin/nox/netapps/networkstate/linkload.so.0.0.0
   /usr/bin/nox/netapps/networkstate/meta.json
   /usr/bin/nox/netapps/networkstate/switchrtt.la
   /usr/bin/nox/netapps/networkstate/switchrtt.so
   /usr/bin/nox/netapps/networkstate/switchrtt.so.0
   /usr/bin/nox/netapps/networkstate/switchrtt.so.0.0.0
   /usr/bin/nox/netapps/route/flowroute_record.la
   /usr/bin/nox/netapps/route/flowroute_record.so
   /usr/bin/nox/netapps/route/flowroute_record.so.0
   /usr/bin/nox/netapps/route/flowroute_record.so.0.0.0
   /usr/bin/nox/netapps/route/meta.json
   /usr/bin/nox/netapps/route/routeinstaller.la
   /usr/bin/nox/netapps/route/routeinstaller.so
   /usr/bin/nox/netapps/route/routeinstaller.so.0
   /usr/bin/nox/netapps/route/routeinstaller.so.0.0.0
   /usr/bin/nox/netapps/route/simplerouting.la
   /usr/bin/nox/netapps/route/simplerouting.so
   /usr/bin/nox/netapps/route/simplerouting.so.0
   /usr/bin/nox/netapps/route/simplerouting.so.0.0.0
   /usr/bin/nox/netapps/routing/__init__.pyc
   /usr/bin/nox/netapps/routing/_pynatenforcer.la
   /usr/bin/nox/netapps/routing/_pynatenforcer.so
   /usr/bin/nox/netapps/routing/_pynatenforcer.so.0
   /usr/bin/nox/netapps/routing/_pynatenforcer.so.0.0.0
   /usr/bin/nox/netapps/routing/_pyrouting.la
   /usr/bin/nox/netapps/routing/_pyrouting.so
   /usr/bin/nox/netapps/routing/_pyrouting.so.0
   /usr/bin/nox/netapps/routing/_pyrouting.so.0.0.0
   /usr/bin/nox/netapps/routing/meta.json
   /usr/bin/nox/netapps/routing/nat_enforcer.la
   /usr/bin/nox/netapps/routing/nat_enforcer.so
   /usr/bin/nox/netapps/routing/nat_enforcer.so.0
   /usr/bin/nox/netapps/routing/nat_enforcer.so.0.0.0
   /usr/bin/nox/netapps/routing/normal_routing.la
   /usr/bin/nox/netapps/routing/normal_routing.so
   /usr/bin/nox/netapps/routing/normal_routing.so.0
   /usr/bin/nox/netapps/routing/normal_routing.so.0.0.0
   /usr/bin/nox/netapps/routing/pynatenforcer.pyc
   /usr/bin/nox/netapps/routing/pynatenforcer_wrap.cc
   /usr/bin/nox/netapps/routing/pyrouting.pyc
   /usr/bin/nox/netapps/routing/pyrouting_wrap.cc
   /usr/bin/nox/netapps/routing/routing_module.la
   /usr/bin/nox/netapps/routing/routing_module.so
   /usr/bin/nox/netapps/routing/routing_module.so.0
   /usr/bin/nox/netapps/routing/routing_module.so.0.0.0
   /usr/bin/nox/netapps/routing/samplerouting.pyc
   /usr/bin/nox/netapps/routing/sprouting.la
   /usr/bin/nox/netapps/routing/sprouting.so
   /usr/bin/nox/netapps/routing/sprouting.so.0
   /usr/bin/nox/netapps/routing/sprouting.so.0.0.0
   /usr/bin/nox/netapps/spanning_tree/__init__.pyc
   /usr/bin/nox/netapps/spanning_tree/meta.json
   /usr/bin/nox/netapps/spanning_tree/spanning_tree.pyc
   /usr/bin/nox/netapps/storage/__init__.pyc
   /usr/bin/nox/netapps/storage/_pystorage.la
   /usr/bin/nox/netapps/storage/_pystorage.so
   /usr/bin/nox/netapps/storage/_pystorage.so.0
   /usr/bin/nox/netapps/storage/_pystorage.so.0.0.0
   /usr/bin/nox/netapps/storage/meta.json
   /usr/bin/nox/netapps/storage/pystorage.pyc
   /usr/bin/nox/netapps/storage/storage-backend.la
   /usr/bin/nox/netapps/storage/storage-backend.so
   /usr/bin/nox/netapps/storage/storage-backend.so.0
   /usr/bin/nox/netapps/storage/storage-backend.so.0.0.0
   /usr/bin/nox/netapps/storage/storage-common.la
   /usr/bin/nox/netapps/storage/storage-common.so
   /usr/bin/nox/netapps/storage/storage-common.so.0
   /usr/bin/nox/netapps/storage/storage-common.so.0.0.0
   /usr/bin/nox/netapps/storage/storage-memleak-test.la
   /usr/bin/nox/netapps/storage/storage-memleak-test.so
   /usr/bin/nox/netapps/storage/storage-memleak-test.so.0
   /usr/bin/nox/netapps/storage/storage-memleak-test.so.0.0.0
   /usr/bin/nox/netapps/storage/storage.pyc
   /usr/bin/nox/netapps/storage/t/__init__.pyc
   /usr/bin/nox/netapps/storage/t/meta.json
   /usr/bin/nox/netapps/storage/t/storage_test.pyc
   /usr/bin/nox/netapps/storage/t/storage_test_base.pyc
   /usr/bin/nox/netapps/storage/t/test_storage.sh
   /usr/bin/nox/netapps/storage/t/test_storage_table_util.sh
   /usr/bin/nox/netapps/storage/util.pyc
   /usr/bin/nox/netapps/switch_management/__init__.pyc
   /usr/bin/nox/netapps/switch_management/_pyswitch_management.la
   /usr/bin/nox/netapps/switch_management/_pyswitch_management.so
   /usr/bin/nox/netapps/switch_management/_pyswitch_management.so.0
   /usr/bin/nox/netapps/switch_management/_pyswitch_management.so.0.0.0
   /usr/bin/nox/netapps/switch_management/meta.json
   /usr/bin/nox/netapps/switch_management/pyswitch_management.pyc
   /usr/bin/nox/netapps/switch_management/switch_management.la
   /usr/bin/nox/netapps/switch_management/switch_management.so
   /usr/bin/nox/netapps/switch_management/switch_management.so.0
   /usr/bin/nox/netapps/switch_management/switch_management.so.0.0.0
   /usr/bin/nox/netapps/switchstats/__init__.pyc
   /usr/bin/nox/netapps/switchstats/_pycswitchstats.la
   /usr/bin/nox/netapps/switchstats/_pycswitchstats.so
   /usr/bin/nox/netapps/switchstats/_pycswitchstats.so.0
   /usr/bin/nox/netapps/switchstats/_pycswitchstats.so.0.0.0
   /usr/bin/nox/netapps/switchstats/cswitchstats.la
   /usr/bin/nox/netapps/switchstats/cswitchstats.so
   /usr/bin/nox/netapps/switchstats/cswitchstats.so.0
   /usr/bin/nox/netapps/switchstats/cswitchstats.so.0.0.0
   /usr/bin/nox/netapps/switchstats/meta.json
   /usr/bin/nox/netapps/switchstats/pycswitchstats.pyc
   /usr/bin/nox/netapps/switchstats/switchstats.pyc
   /usr/bin/nox/netapps/tablog/flowlog.la
   /usr/bin/nox/netapps/tablog/flowlog.so
   /usr/bin/nox/netapps/tablog/flowlog.so.0
   /usr/bin/nox/netapps/tablog/flowlog.so.0.0.0
   /usr/bin/nox/netapps/tablog/meta.json
   /usr/bin/nox/netapps/tablog/rttlog.la
   /usr/bin/nox/netapps/tablog/rttlog.so
   /usr/bin/nox/netapps/tablog/rttlog.so.0
   /usr/bin/nox/netapps/tablog/rttlog.so.0.0.0
   /usr/bin/nox/netapps/tablog/tablog.la
   /usr/bin/nox/netapps/tablog/tablog.so
   /usr/bin/nox/netapps/tablog/tablog.so.0
   /usr/bin/nox/netapps/tablog/tablog.so.0.0.0
   /usr/bin/nox/netapps/tests/__init__.pyc
   /usr/bin/nox/netapps/tests/_pytests.la
   /usr/bin/nox/netapps/tests/_pytests.so
   /usr/bin/nox/netapps/tests/_pytests.so.0
   /usr/bin/nox/netapps/tests/_pytests.so.0.0.0
   /usr/bin/nox/netapps/tests/cacert.pem
   /usr/bin/nox/netapps/tests/meta.json
   /usr/bin/nox/netapps/tests/pytests.pyc
   /usr/bin/nox/netapps/tests/pyunittests/__init__.pyc
   /usr/bin/nox/netapps/tests/pyunittests/bs_link_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/componentws_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/controller_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/dhcp_parse_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/dns_parse_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/eap_parse_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/ethernet_parse_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/event_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/icmp_parse_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/ipv4_parse_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/lldp_parse_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/mod_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/routing_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/simple_async_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/tcp_parse_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/transactional_storage_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/udp_parse_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/util_parse_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/vlan_parse_test.pyc
   /usr/bin/nox/netapps/tests/pyunittests/webservice_test.pyc
   /usr/bin/nox/netapps/tests/servercert.pem
   /usr/bin/nox/netapps/tests/serverkey.pem
   /usr/bin/nox/netapps/tests/tests.la
   /usr/bin/nox/netapps/tests/tests.so
   /usr/bin/nox/netapps/tests/tests.so.0
   /usr/bin/nox/netapps/tests/tests.so.0.0.0
   /usr/bin/nox/netapps/tests/unittest.pyc
   /usr/bin/nox/netapps/topology/__init__.pyc
   /usr/bin/nox/netapps/topology/_pytopology.la
   /usr/bin/nox/netapps/topology/_pytopology.so
   /usr/bin/nox/netapps/topology/_pytopology.so.0
   /usr/bin/nox/netapps/topology/_pytopology.so.0.0.0
   /usr/bin/nox/netapps/topology/meta.json
   /usr/bin/nox/netapps/topology/pytopology.pyc
   /usr/bin/nox/netapps/topology/pytopology_test.pyc
   /usr/bin/nox/netapps/topology/pytopology_wrap.cc
   /usr/bin/nox/netapps/topology/topology.la
   /usr/bin/nox/netapps/topology/topology.so
   /usr/bin/nox/netapps/topology/topology.so.0
   /usr/bin/nox/netapps/topology/topology.so.0.0.0
   /usr/bin/nox/netapps/user_event_log/__init__.pyc
   /usr/bin/nox/netapps/user_event_log/_pyuser_event_log.la
   /usr/bin/nox/netapps/user_event_log/_pyuser_event_log.so
   /usr/bin/nox/netapps/user_event_log/_pyuser_event_log.so.0
   /usr/bin/nox/netapps/user_event_log/_pyuser_event_log.so.0.0.0
   /usr/bin/nox/netapps/user_event_log/meta.json
   /usr/bin/nox/netapps/user_event_log/networkeventsws.pyc
   /usr/bin/nox/netapps/user_event_log/py_uel_memleak_test.pyc
   /usr/bin/nox/netapps/user_event_log/pyuser_event_log.pyc
   /usr/bin/nox/netapps/user_event_log/simple_uel_util.pyc
   /usr/bin/nox/netapps/user_event_log/uel_memleak_test.la
   /usr/bin/nox/netapps/user_event_log/uel_memleak_test.so
   /usr/bin/nox/netapps/user_event_log/uel_memleak_test.so.0
   /usr/bin/nox/netapps/user_event_log/uel_memleak_test.so.0.0.0
   /usr/bin/nox/netapps/user_event_log/user_event_log.la
   /usr/bin/nox/netapps/user_event_log/user_event_log.so
   /usr/bin/nox/netapps/user_event_log/user_event_log.so.0
   /usr/bin/nox/netapps/user_event_log/user_event_log.so.0.0.0
   /usr/bin/nox/netapps/user_event_log/user_event_log_test2.la
   /usr/bin/nox/netapps/user_event_log/user_event_log_test2.so
   /usr/bin/nox/netapps/user_event_log/user_event_log_test2.so.0
   /usr/bin/nox/netapps/user_event_log/user_event_log_test2.so.0.0.0
   /usr/bin/nox/netapps/nddi/__init__.pyc
   /usr/bin/nox/netapps/nddi/meta.json
   /usr/bin/nox/netapps/nddi/nddi_dbus.pyc
   /usr/bin/nox/webapps/__init__.pyc
   /usr/bin/nox/webapps/miscws/__init__.pyc
   /usr/bin/nox/webapps/miscws/cpustats.pyc
   /usr/bin/nox/webapps/miscws/meta.json
   /usr/bin/nox/webapps/webserver/__init__.pyc
   /usr/bin/nox/webapps/webserver/dummywebpage.pyc
   /usr/bin/nox/webapps/webserver/meta.json
   /usr/bin/nox/webapps/webserver/webauth.pyc
   /usr/bin/nox/webapps/webserver/webserver.pyc
   /usr/bin/nox/webapps/webserver/www/0/nox/webapps/webserver/happy_face.png
   /usr/bin/nox/webapps/webservice/__init__.pyc
   /usr/bin/nox/webapps/webservice/meta.json
   /usr/bin/nox/webapps/webservice/web_arg_utils.pyc
   /usr/bin/nox/webapps/webservice/webservice.pyc
   /usr/bin/nox/webapps/webserviceclient/__init__.pyc
   /usr/bin/nox/webapps/webserviceclient/async.pyc
   /usr/bin/nox/webapps/webserviceclient/simple.pyc
   /usr/bin/nox/webapps/webserviceclient/t/TEST_DIRECTORY
   /usr/bin/nox/webapps/webserviceclient/t/__init__.pyc
   /usr/bin/nox/webapps/webserviceclient/t/unit_test_db
   /usr/bin/nox/webapps/webserviceclient/t/ws_test.pyc
   /usr/bin/nox/webapps/webserviceclient/t/ws_testdefs.sh
   /usr/bin/nox_core
   /usr/bin/reset-admin-pw
   /usr/bin/switch_command.pyc
   /usr/lib64/libnoxcore.la
   /usr/lib64/libnoxcore.so
   /usr/lib64/libnoxcore.so.0
   /usr/lib64/libnoxcore.so.0.0.0
   /usr/share/man/man1/start-test-vm.1.gz
   /usr/share/man/man1/stop-test-vm.1.gz
   /usr/share/man/man5/vms.conf.5.gz
   /usr/share/noxca.cnf

%doc

%post
if [ $1 -eq 1 ]; then
        #--- install

  #add the tdor user
  /usr/sbin/groupadd _oess
  /usr/sbin/useradd  -r -m  -c "NOX User" -d /var/log/nox -s /bin/bash -g _oess _oess


fi


if [ $1 -ge 2 ]; then
   /usr/sbin/usermod -s /bin/bash _oess
fi

touch /usr/bin/nox.info
touch /var/run/nox.pid
mkdir /var/run/nox
chown _oess /usr/bin/nox.info
chown _oess /var/run/nox.pid
chown -R _oess:_oess /var/run/nox
chown -R _oess:_oess /var/log/nox

%postun
rm /usr/bin/nox.info
rm /var/run/nox.pid


%changelog

