#!/usr/bin/perl

use strict;
use warnings;

use OESS::DBus;

use SOAP::Lite;
use SOAP::Transport:HTTP;

SOAP::Transport::HTTP::CGI->dispatch_to('OESS::NSI::Server')->handle;