use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'OESS::Topology',
    AUTHOR              => 'GMOC Systems Engineering <syseng@grnoc.iu.edu>',
    VERSION_FROM        => 'lib/OESS/Topology.pm',
#ABSTRACT_FROM       => 'lib/GMOC/DB.pm',
              PL_FILES            => {},
              PREREQ_PM => {
                  'Carp'=>0,
                  'DBI'=> 0,
                  'Test::More'=> 0,
                  'XML::Simple'=> 0,
                  'XML::XPath' => 0,
              },
              dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
              clean               => { FILES => 'GMOC-Config-*' },
              );


