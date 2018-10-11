use OESS::Interface;
use Test::More tests => 1;
use Log::Log4perl;
use OESS::Database;
use OESS::DB::Interface;

$OESS::Database::ENABLE_DEVEL=1;
Log::Log4perl->init("/etc/oess/logging.conf");
my $db = OESS::Database->new();
my $interface = OESS::Interface->new(	db 	=> $db,
					name	=> "asd",
					node	=> 
						);
ok(defined($interface),"Object interface initiated");
