#!/usr/bin/perl
#
#
use strict;
use warnings;
use Data::Dumper::Concise;
use Net::IP;

#my $blacklist = '/usr/local/etc/nftables.d/blacklist.nft';
my $blacklist = './blacklist.nft';
my $mod_time = (stat($blacklist))[9];

my $ips = get_ips();
print Dumper($ips);

my $range_start;
my $range_end;
my $total_blocks;
foreach my $addr (@$ips) {
    my ($start, $end) = get_range($addr);
    if(defined($range_start)) {
        if($start == $range_end + 1) {
            $range_end = $end;
        } else {
            my $blocks = to_blocks($range_start, $range_end);
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
    my $blocks = to_blocks($range_start, $range_end);
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

print "mod_time = $mod_time\n";
my $new_mod_time = (stat($blacklist))[9];
print "new_mod_time = $new_mod_time\n";

if($mod_time == $new_mod_time) {
    print "update\n";
    rename($blacklist, $old);
    rename($new, $blacklist);
    print "old: $old\n";
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


# takes two decimal network addresses
# returns a set of network blocks that cover the range
sub to_blocks {
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


sub get_range {
    my ($addr) = @_;

    my ($ip,$len) = ($addr =~ m/^([0-9\.]*)(?:\/(.*))?$/);
    $len = 32 unless($len);
    my $dec = 0;
    foreach my $part (split(/\./, $ip)) {
        $dec = $dec * 256 + $part;
    }
    my $mask = (2 ** (32 - $len) - 1);
    my $start = $dec & (~$mask);
    my $end = $start | $mask;

    return($start, $end);
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

sub get_ips {
    my $ips;
    open(my $fh, '<', $blacklist) or die "$blacklist: $!";
    foreach my $line (<$fh>) {
        if($line =~ m/{ (.*) }/) {
            push(@$ips, $1);
        }
    }
    close($fh);

    my $sorted = [
        map substr($_, 4),
           sort
              map pack('C4a*', (split(/[\.\/]/))[0..3], $_),
                 @$ips
    ];

    return($sorted);
}
