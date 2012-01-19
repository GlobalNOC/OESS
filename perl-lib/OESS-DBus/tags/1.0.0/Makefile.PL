use strict;
use warnings;
use ExtUtils::MakeMaker;
use Config;


my $librrd;
if ($^O eq 'darwin'){
    $librrd = '-lrrd_th';
}
else {
    $librrd = "-L../../src/.libs/ -lrrd_th -lpthread";
}

WriteMakefile(
    'NAME'         => 'OESS::DBus',
    'AUTHOR'       => 'GRNOC Software Engineering <software@grnoc.iu.edu>',
    'VERSION_FROM' => 'lib/OESS/DBus.pm',
    'DEFINE'       => "-DPERLPATCHLEVEL=$Config{PATCHLEVEL}",
    'LDFROM'       => '$(OBJECT) '.$librrd, 
    'realclean'    => {FILES => 't/demo?.rrd t/demo?.png' },
    ($^O eq 'darwin') ? ( 'LDDLFLAGS'    => "-L../../src/.libs/ $Config{lddlflags}" ) : ()
    );
