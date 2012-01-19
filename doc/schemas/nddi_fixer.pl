#!/usr/bin/perl

use strict;
use Data::Dumper;

my %enum_list =( circuit_instantiation => {circuit_state => ['scheduled','deploying','active','decom']},
                  node => {operational_state =>['unknown','up','down'] },
                  node_instantiation => {admin_state => ['planned','available','active','maintenance','decom']},
                  interface => {operational_state =>['unknown','up','down'],role => ['unknown','trunk','customer'] },
                  link_instantiation => {link_state => ['planned','available','active','maintenance','decom']},
                  path_instantiation => {'path_state' => ['active','available','deploying']},
                  path => {'path_type' => ['primary','backup']},

                  );

warn Dumper(\%enum_list);

sub add_quotes{
   return "'$_'";
}

sub main{

   my $current_table_name="";
   while(<>){
      my $line=$_;
      if($line =~ /CREATE TABLE (?:nddi.)?(\w+)/ ){
         $current_table_name=$1;
         #warn "current_table=$current_table_name\n";
      }

      if ($line =~/(\w+_state)\sINT/){
         my $row_name=$1;

         if(defined $enum_list{$current_table_name}{$row_name}){
             warn "$row_name got it\n";
             my $enum_values;
             #print Dumper($enum_list{$current_table_name}{$row_name});
             $enum_values=$enum_list{$current_table_name}{$row_name};
             $line="\t\t$row_name ENUM (".join(",",map(add_quotes,@$enum_values)).") NOT NULL default '".$enum_values->[0]."',\n";
            # print $line;
         }  
          
      }
      print $line;
   }
}

main();

