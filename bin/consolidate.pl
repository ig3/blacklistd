#!/usr/bin/perl
#
# Consolidate ranges of ip addresses in the blacklist.
#
# When an nftables set has flag interval, intervals of
# IP addresses may be added to the set. There are two
# formats for adding intervals:
#
#   225.0.0.0/24,
#   225.0.1.0-225.0.1.17
#
# When the form address/mask is used, it is possible
# to specify an address with bits set in the host range
# (e.g. 225.0.0.7/24) but these will be ignored and
# the network address will be that with the host address
# of 0 (e.g. 225.0.0.0 in the previous example).
#
# When the form address-address is used, arbitrary starting
# and ending addresses may be specified.
#
use strict;
use warnings;
use Data::Dumper::Concise;
use Net::IP;

my $blacklist = '/usr/local/etc/nftables.d/blacklist.nft';
#my $blacklist = './blacklist.nft';
my $mod_time = (stat($blacklist))[9];

my $intervals = get_intervals();
print Dumper($intervals);

my $range_start;
my $range_end;
my $total_blocks;
foreach my $interval (@$intervals) {
    my ($start, $end) = get_range($interval);
    if(defined($range_start)) {
        if($start <= $range_end + 1) {
            $range_end = $end if($end > $range_end);
        } else {
            #            my $blocks = to_cidr_blocks($range_start, $range_end);
            my $blocks = to_nft_interval($range_start, $range_end);
            push(@$total_blocks, @$blocks);
            $range_start = $start;
            $range_end = $end;
        }
    } else {
        $range_start = $start;
        $range_end = $end;
    }
}

if(defined($range_start)) {
    #    my $blocks = to_cidr_blocks($range_start, $range_end);
    my $blocks = to_nft_interval($range_start, $range_end);
    push(@$total_blocks, @$blocks);
}


my $nft = blocks_to_nft($total_blocks);

print "$nft";


my $old = $blacklist;
$old =~ s/\.nft$/.old/;
my $new = $blacklist;
$new =~ s/\.nft$/.new/;
open(my $fh, '>', $new) or die "$new: $!";
print $fh $nft;
close($fh);

print $nft;

print "mod_time = $mod_time\n";
my $new_mod_time = (stat($blacklist))[9];
print "new_mod_time = $new_mod_time\n";

if($mod_time == $new_mod_time) {
    print "update\n";
    #    rename($blacklist, $old);
    #    rename($new, $blacklist);
    #    print "old: $old\n";
}

exit(0);


sub blocks_to_nft {
    my ($blocks) = @_;

    my $nft = '';

    foreach my $block (@$blocks) {
        $nft .= "add element inet filter blacklist { $block }\n";
    }

    return($nft);
}


sub to_nft_interval {
    my ($start, $end) = @_;
    if($start == $end) {
        return([ to_dd($start) ]);
    } else {
        return([ to_dd($range_start) . '-' . to_dd($range_end) ]);
    }
}

# takes two decimal network addresses
# returns a set of network blocks that cover the range
sub to_cidr_blocks {
    my ($start, $end) = @_;

    my $blocks;

    while($start < $end) {

        # get the number of trailing 0 bits in the start address
        my $len = 1;
        while(
            $len < 32 and
            (($start >> $len) << $len) == $start and
            ($start + 2 ** $len -1) <= $end
        ) {
            $len++;
        }
        $len--;

        if($len == 0) {
            push(@$blocks, to_dd($start));
        } else {
            push(@$blocks, to_dd($start) . "/" . (32-$len));
        }
        $start = $start + (2 ** $len);
    }

    if($start == $end) {
        push(@$blocks, to_dd($start));
    }

    return($blocks);
}


# return tuple ($start,$end) where start and end
# are decimal network addresses.
sub get_range {
    my ($addr) = @_;

    my $start;
    my $end;

    if($addr =~ m/^(.*)-(.*)$/) {
        $start = to_dec($1);
        $end = to_dec($2);
    } elsif($addr =~ m/^(.*)\/(.*)$/) {
        my $mask = (2 ** (32 - $2) - 1);
        $start = to_dec($1) & (~$mask);
        $end = $start | $mask;
    } else {
        $start = to_dec($addr);
        $end = $start;
    }

    return($start, $end);
}



sub to_dec {
    my ($addr) = @_;

    my $dec = 0;
    foreach my $part (split(/\./, $addr)) {
        $dec = $dec * 256 + $part;
    }
    return($dec);
}


# Convert a decimal address to dotted decimal
sub to_dd {
    my ($addr) = @_;

    my $p4 = $addr % 256;
    $addr /= 256;
    my $p3 = $addr % 256;
    $addr /= 256;
    my $p2 = $addr % 256;
    $addr /= 256;
    my $p1 = $addr % 256;

    return("$p1.$p2.$p3.$p4");
}

sub get_intervals {
    my $intervals;
    open(my $fh, '<', $blacklist) or die "$blacklist: $!";
    foreach my $line (<$fh>) {
        if($line =~ m/{ (.*) }/) {
            push(@$intervals, $1);
        }
    }
    close($fh);

    my $sorted = [
        map substr($_, 4),
           sort
              map pack('C4a*', (split(/[\.\/]/))[0..3], $_),
                 @$intervals
    ];

    return($sorted);
}
