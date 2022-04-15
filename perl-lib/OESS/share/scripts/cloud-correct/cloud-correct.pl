=head1 cloud-correct

Corrects issue that occurred during migration: Cloud connection
details were not moved with the rest of the endpoint.

=cut

use strict;
# use warnings;

use Data::Dumper;
use OESS::DB;
use OESS::Endpoint;
use Text::CSV;


my $l2 = "./circuit_cloud_eps.csv";
my $l3 = "./vrf_cloud_eps.csv";


=head2

    my $rows = load_csv("./file.csv");

load_csv opens $file and then returns an array of dicts using the keys
set in the first line of the CSV.

=cut
sub load_csv {
  my $file = shift;

  my $csv = new Text::CSV();
  my $rows = [];

  open my $fh, "<:encoding(utf8)", $file or die "$file: $!";
  $csv->column_names($csv->getline($fh));
  while (my $row = $csv->getline_hr($fh)) {
    push @$rows, $row;
  }
  close $fh;

  return $rows;
}


=head2 cloud_eps_without_connection_details

    my $eps = cloud_eps_without_connection_details($db, 'l2');

=cut
sub cloud_eps_without_connection_details {
    my $db   = shift;
    my $type = shift;

    my $query = "";
    if ($type eq 'l2') {
        $query = "
            select *
            from circuit join circuit_instantiation on circuit.circuit_id=circuit_instantiation.circuit_id
            join circuit_edge_interface_membership as circuit_ep on circuit.circuit_id=circuit_ep.circuit_id
            join interface on circuit_ep.interface_id=interface.interface_id
            where interface.cloud_interconnect_type is not NULL and circuit_instantiation.circuit_state='active' and circuit_instantiation.end_epoch=-1 and circuit_ep.end_epoch=-1 and circuit_ep.circuit_edge_id not in
                (select circuit_ep_id from cloud_connection_vrf_ep where circuit_ep_id is not NULL);
        ";
    } else {
        $query = "
            select *
            from vrf join vrf_ep on vrf.vrf_id=vrf_ep.vrf_id
            join interface on vrf_ep.interface_id=interface.interface_id
            where interface.cloud_interconnect_type is not NULL and vrf.state!='decom' and vrf_ep.state!='decom' and vrf_ep_id not in
                (select vrf_ep_id from cloud_connection_vrf_ep where vrf_ep_id is not NULL);
        ";
    }

    my $result = $db->execute_query($query, []);
    return $result;
}

my $found_l2_backup_lookup_counter  = 0;
my $failed_l2_backup_lookup_counter = 0;

my $found_l3_backup_lookup_counter  = 0;
my $failed_l3_backup_lookup_counter = 0;

sub get_l2_ep {
    my $old_l2eps = shift;
    my $new       = shift; # new endpoint

    foreach my $old (@$old_l2eps) {
        if (!defined $old->{inner_tag} || $old->{inner_tag} eq '\\N') {
            $old->{inner_tag} = undef;
        }

        if ($old->{circuit_id} == $new->{circuit_id} && $old->{extern_vlan_id} == $new->{extern_vlan_id} && $old->{inner_tag} == $new->{inner_tag}) {
            $found_l2_backup_lookup_counter += 1;
            # warn "Found possible backup of cloud connection details for l2conn $new->{circuit_id} endpoint $new->{circuit_edge_id}. [$found_l2_backup_lookup_counter]";
            return $old;
        }
    }

    $failed_l2_backup_lookup_counter += 1;
    warn "Couldn't find backup cloud connection details for l2conn $new->{circuit_id}. [$failed_l2_backup_lookup_counter]";
    return;
}


sub get_l3_ep {
    my $old_l3eps = shift;
    my $new       = shift; # new endpoint

    foreach my $old (@$old_l3eps) {
        if (!defined $old->{inner_tag} || $old->{inner_tag} eq '\\N') {
            $old->{inner_tag} = undef;
        }

        if ($old->{vrf_id} == $new->{vrf_id} && $old->{tag} == $new->{tag} && $old->{inner_tag} == $new->{inner_tag}) {
            $found_l3_backup_lookup_counter += 1;
            # warn "Found possible backup of cloud connection details for l3conn $new->{vrf_id} endpoint $new->{vrf_ep_id}. [$found_l3_backup_lookup_counter]";
            return $old;
        }
    }

    $failed_l3_backup_lookup_counter += 1;
    warn "Couldn't find backup cloud connection details for l3conn $new->{vrf_id} endpoint $new->{vrf_ep_id}. [$failed_l3_backup_lookup_counter]";
    return;
}


sub main {
    my $old_l2eps = load_csv($l2);
    my $old_l3eps = load_csv($l3);

    warn "Loading data for " . scalar @$old_l2eps . " l2 endpoints from backup.";
    warn "Loading data for " . scalar @$old_l3eps . " l3 endpoints from backup.";

    warn Dumper('###');

    my $db = new OESS::DB();
    $db->start_transaction;
    
    my $new_l2eps = cloud_eps_without_connection_details($db, 'l2');
    my $new_l3eps = cloud_eps_without_connection_details($db, 'l3');

    my $l2_missing_data_count = scalar @$new_l2eps;
    my $l3_missing_data_count = scalar @$new_l3eps;

    warn "Missing data for $l2_missing_data_count l2 endpoints.";
    warn "Missing data for $l3_missing_data_count l3 endpoints.";

    foreach my $new_l2ep (@$new_l2eps) {
        my $old_l2ep = get_l2_ep($old_l2eps, $new_l2ep);
        next if !defined $old_l2ep;

        my $ep = new OESS::Endpoint(db => $db, type => 'circuit', circuit_id => $new_l2ep->{circuit_id}, interface_id => $new_l2ep->{interface_id});
        $ep->cloud_account_id($old_l2ep->{cloud_account_id});
        $ep->cloud_connection_id($old_l2ep->{cloud_connection_id});

        warn "L2CONN[$ep->{circuit_id}]($ep->{interface}): Setting cloud_connection_id: $ep->{cloud_connection_id} cloud_account_id: $ep->{cloud_account_id}";
        $ep->update_db;
    }

    foreach my $new_l3ep (@$new_l3eps) {
        my $old_l3ep = get_l3_ep($old_l3eps, $new_l3ep);
        next if !defined $old_l3ep;

        my $ep = new OESS::Endpoint(db => $db, type => 'vrf', vrf_endpoint_id => $new_l3ep->{vrf_ep_id});
        $ep->cloud_account_id($old_l3ep->{cloud_account_id});
        $ep->cloud_connection_id($old_l3ep->{cloud_connection_id});

        warn "L3CONN[$ep->{vrf_id}]($ep->{interface}): Setting cloud_connection_id: $ep->{cloud_connection_id} cloud_account_id: $ep->{cloud_account_id}";
        $ep->update_db;
    }

    $db->commit;

    warn "Couldn't find backup data for $failed_l2_backup_lookup_counter \/ $l2_missing_data_count l2 connections.";
    warn "Found possible backup data for $found_l2_backup_lookup_counter \/ $l2_missing_data_count l2 connections.";

    warn "Couldn't find backup data for $failed_l3_backup_lookup_counter \/ $l3_missing_data_count l3 connections.";
    warn "Found possible backup data for $found_l3_backup_lookup_counter \/ $l3_missing_data_count l3 connections.";

    return 0;
}

main();
