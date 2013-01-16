use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'OESS::Syslogger',
    AUTHOR              => 'GRNOC Systems Engineering <syseng@grnoc.iu.edu>',
    VERSION_FROM        => 'lib/OESS/Syslogger.pm',
              PL_FILES            => {},
              PREREQ_PM => {
                  'Carp'=>0,
                  'DBI'=> 0,
                  'Test::More'=> 0,
              },
              dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
              clean               => { FILES => 'GRNOC-Syslogger*' },
              );


