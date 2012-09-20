include ../../../Make.vars

EXTRA_DIST = \
	__init__.py\
	meta.json\
	nddi_dbus.py
	nddi_dbus_readonly.py
if PY_ENABLED
AM_CPPFLAGS += $(PYTHON_CPPFLAGS)
NOX_RUNTIMEFILES = meta.json\
	__init__.py\
	nddi_dbus.py
	nddi_dbus_readonly.py

endif #PY_ENABLED

all-local:  nox-all-local
clean-local: nox-clean-local
install-exec-hook: nox-install-local

