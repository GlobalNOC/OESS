
%define ostag unknown

%define is_rh   %(test -e /etc/redhat-release && echo 1 || echo 0)
%define is_fc   %(test -e /etc/fedora-release && echo 1 || echo 0)

%if %{is_fc}
%define ostag %(sed -e 's/^.*release /fc/' -e 's/ .*$//' -e 's/\\./_/g' < /etc/fedora-release)
%else
%if %{is_rh}
%define ostag %(sed -e 's/^.*release /rh/' -e 's/ .*$//' -e 's/\\./_/g' < /etc/redhat-release)
%endif
%endif

%define release 2.%{ostag}

Summary:  YUI library 2
Name: yui2
Version: 2.9.0
Release: %{release}
License: GPL
Group:   Applications/Network
URL:     http://yuilibrary.com/downloads/yui2/yui_2.9.0.zip
Source0: yui_%{version}.zip
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
BuildRequires: unzip, zip
BuildArch:      noarch

%description
YUI 2.8.1 javascript library


%define destdir   /gmoc/yui/2.8.1
%define httpdir   /etc/httpd/conf.d

%prep
%setup -n yui

%build

%install
rm -rf %{buildroot}
%{__install} -d -m0755 %{buildroot}/usr/share/yui2/
cp -ar  build/*            %{buildroot}/usr/share/yui2/
find . -type f |grep build |sed 's:./build:/usr/share/yui2/:' > $RPM_BUILD_DIR/file.list.%{name}

%clean
rm -rf %{buildroot}

%files -f ../file.list.%{name}
#%files 
#%defattr(-,root,root)
#%{buildroot}/gnoc/yui/%{version}/*

%post

%postun

