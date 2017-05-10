Summary: OESS MetaPackage 
Name: oess
Version: 1.2.0
Release: 0.dev01%{?dist}
License: Apache
Group: GRNOC
#Source: 
URL: http://globalnoc.iu.edu
Buildroot: %{_tmppath}/%{name}-root
Requires: oess-core >= 1.2.0
Requires: oess-frontend >= 1.2.0

%description
Package that installs all of the OESS packages

%pre

%post


%changelog
* Tue Dec 13 2011 Andrew Ragusa <aragusa@nddi-dev.bldc.net.internet2.edu> - 
- Initial build.

