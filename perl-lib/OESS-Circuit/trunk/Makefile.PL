use strict;
use warnings;
use ExtUtils::MakeMaker;

sub MY::postamble { << 'END';}
rpm:	dist
	rpmbuild -ta OESS-Circuit-$(VERSION).tar.gz
END

WriteMakefile(
    NAME                => 'OESS::Circuit',
    AUTHOR              => 'GRNOC Systems Engineering <syseng@grnoc.iu.edu>',
    VERSION_FROM        => 'lib/OESS/Circuit.pm',
    ABSTRACT_FROM       => 'lib/OESS/Circuit.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'DBI'=> 0,
        'XML::Simple'=> 0,
        'Array::Utils' => 0,
        'Net::DBus' => 0
},
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'OESS-Circuit-*' },
    );

sub MY::test
{
    q(
TEST_VERBOSE=1
test : pure_all
	$(FULLPERL) t/TEST $(TEST_VERBOSE)

test_jenkins : pure_all
	$(FULLPERL) t/TEST $(TEST_VERBOSE) --formatter=TAP::Formatter::Console

    );
}
