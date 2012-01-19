#!/usr/bin/perl
#
#
#
use strict;

use Net::Ping;
use Term::ReadKey;
use Time::HiRes  qw( usleep ualarm gettimeofday tv_interval nanosleep
 clock_gettime clock_getres clock_nanosleep clock
 stat );

my $interface_name="eth6";
my $vlan_start=100;
my $num_vlans=800;

sub create_config_vlans{
  my $suffix=shift;
   

  for (my $i=0;$i<$num_vlans;$i++){
      my $vlan_id=$vlan_start+$i;
      system("vconfig add $interface_name $vlan_id");
      #now the ip address
      my $base_net="10";
      my $part1=int($i/256);
      my $part2=int($i%256);
      system("ifconfig $interface_name.$vlan_id $base_net.$part1.$part2.$suffix/24 up");

  }

}

sub remove_vlans{

   return;

  for (my $i=0;$i<$num_vlans;$i++){
      my $vlan_id=$vlan_start+$i;
      system("vconfig rem $interface_name.$vlan_id");
  }


}

sub do_test{
  for (my $i=0;$i<$num_vlans;$i++){
      my $vlan_id=$vlan_start+$i;
      my $call1="dpctl add-flow tcp:156.56.6.70 dl_vlan=$vlan_id,in_port=22,idle_timeout=600,actions=output:24";
      my $call2="dpctl add-flow tcp:156.56.6.70 dl_vlan=$vlan_id,in_port=24,idle_timeout=600,actions=output:22";
      system($call1);
      system($call2);   
      usleep(50000);
   }

   my $p = Net::Ping->new("icmp");
    my @host_array;
   for (my $i=0;$i<$num_vlans;$i++){
      my $vlan_id=$vlan_start+$i;
      my $base_net="10";
      my $part1=int($i/256);
      my $part2=int($i%256);
      push(@host_array,"$base_net.$part1.$part2.1");
   }
  
 my $failure_count=0; 
 foreach my $host (@host_array)
  {
   print "$host is ";
   #print "NOT " unless $p->ping($host, 2);
   if(not $p->ping($host, 2)){
      print "NOT "; 
      $failure_count++;
   }
   print "reachable.\n";
# # sleep(1);
 }
 $p->close();
 print "fail_count=$failure_count total_count=$num_vlans\n";

}

sub wait_until_key{

    print "Press any key to continue\n";
    ReadMode 4; # Turn off controls keys
    ReadKey(0);
    ReadMode 0; # Reset tty mode before exiting

}

sub server{
    create_config_vlans("1");
    do_test();
    wait_until_key();
    remove_vlans();
    print "done\n";

}

sub client{
    create_config_vlans("2");
    do_test();
    wait_until_key();
    remove_vlans();
    print "done\n";
}


sub main{
    client();

}

main();



