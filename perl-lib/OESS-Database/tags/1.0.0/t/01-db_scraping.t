#!perl -T

use Test::More;

my $num_tests=2;

BEGIN {
    use_ok( 'OESS::Database' );
}

my $config_filename="/etc/oess/db_testing.xml";

SKIP: {
    skip "No testing config file found",1  if(not -e $config_filename);
    
    my $db = OESS::Database->new(config => $config_filename);
    
    $db->reset_database(config=>$config_filename);
    
    $OESS::Database::ENABLE_DEVEL=1;
    
    $db->reset_database(config=>$config_filename);
    
    pass("some noop");
}

done_testing($num_tests);


