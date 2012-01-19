#!perl -T

use Test::More ;
use XML::Simple;
use Data::Dumper;

my $num_tests=4;

BEGIN {
        use_ok( 'OESS::Database' );
}
 my $config_filename="/etc/oess/db_testing.xml";

SKIP: {
   skip "No testing config file found",1  if(not -e $config_filename);

   my $db = OESS::Database->new(config => $config_filename);

   # should fail, devel mode not enabled
   ok(! $db->reset_database(), "resetting database without devel mode on");
   
   # set devel mode on
   $OESS::Database::ENABLE_DEVEL=1;

   # should succeed now
   ok($db->reset_database(), "resetting database with devel mode on");
      
   # load an XML file into the database
   ok($db->add_into(xml_dump => "t/xml_dumps/dump1.xml"), "loaded xml dump into database");

}

done_testing($num_tests);

#diag( "Testing GMOC::Common $GMOC::Config::VERSION, Perl $], $^X\n" );

