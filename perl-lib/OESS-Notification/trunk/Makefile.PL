use strict;
use warnings;
use ExtUtils::MakeMaker;

sub MY::postamble { <<"END"; }

rpm: dist
	rpmbuild -ta OESS-Notification-\$(VERSION).tar.gz

END

WriteMakefile(
              NAME                => 'OESS::Notification',
              AUTHOR              => 'GRNOC System Engineering <syseng@grnoc.iu.edu>',
              VERSION_FROM        => 'lib/OESS/Notification.pm',
              ABSTRACT_FROM       => 'lib/OESS/Notification.pm',
              PL_FILES            => {},
              PREREQ_PM => {
                            'OESS::Database' => 0,
                           },
              dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
              clean               => { FILES => 'OESS-Notification-*' },
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

