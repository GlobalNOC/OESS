Summary: OESS Metapackage 
Name: oess
Version: 2.0.10
Release: 2%{?dist}
License: Apache
Group: GRNOC
#Source: 
URL: http://globalnoc.iu.edu
Buildroot: %{_tmppath}/%{name}-root
Requires: oess-core >= 2.0.10
Requires: oess-frontend >= 2.0.10

%description
Package that installs all of the OESS packages

%pre

%post


%changelog
* Tue Dec 13 2011 Andrew Ragusa <aragusa@nddi-dev.bldc.net.internet2.edu> - 
- Initial build.

