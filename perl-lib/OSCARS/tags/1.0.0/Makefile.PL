use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'OSCARS::Client',
    AUTHOR              => 'Globalnoc Systems Engineering <syseng@grnoc.iu.edu>',
    VERSION_FROM        => 'lib/OSCARS/Client.pm',
              PL_FILES            => {},
              PREREQ_PM => {
                  'LWP::UserAgent'=>0,
                  'Test::More'=> 0,
                  'XML::XPath' => 0,
              },
              dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
              clean               => { FILES => 'OSCARS-Client-*' },
              );


