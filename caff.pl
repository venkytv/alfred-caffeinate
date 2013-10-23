#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin;
use Storable qw( lock_nstore lock_retrieve );

my $CAFFEINATE_FLAGS = 'is';

my $active_sleep = 0;
my $cache = 'intervals.cache';
my @defaults = qw( 15m 1h 5h );
my %intervals = ();

# Hand-crafted XML! I know, sorry!
# Don't want dependencies for something as simple as this.
sub genfeedback($) {
    my $list = shift;
    my $xml = <<HEAD;
<?xml version="1.0"?>
<items>
HEAD

    foreach my $item (@$list) {
        my $title = $item->{title};
        my $subtitle = $item->{subtitle};
        my $cancellable = $item->{cancellable};

        if ($active_sleep and $cancellable) {
            $title =~ s/^(.)/Cancel existing and \L$1/;
            $subtitle =~ s/^(.)/Cancel existing and \L$1/;
        }

        my $valid = (exists $item->{valid} ? $item->{valid} : 'yes');

        $xml .=     '    <item';
        foreach my $opt (qw( uid arg autocomplete )) {
            if (exists $item->{$opt}) {
                $xml .= ' ' . $opt . '="' . $item->{$opt} . '"';
            }
        }
        $xml .= "\n";
        $xml .= <<ITEM;
          valid="$valid">
        <title>$title</title>
        <subtitle>$subtitle</subtitle>
    </item>
ITEM
    }

    $xml .= <<FOOT;
</items>
FOOT

    return $xml;
}

sub check_existing_caffeinate_task() {
    # TODO: Retrieve existing caffeinate task and timeout duration
    #       from 'pmset -g assertions'
    return (int(rand(3)) ? '10 minutes' : 0);
}

sub enable_caffeinate($) {
    my $str = shift;

    my ($dur, $unit) = $str =~ /(\d+)([hm])/;
    if (not $dur or not $unit) {
        return "ERROR enabling caffeinate\n";
    }

    # Store duration in frequently used interval cache
    my $i = (-f $cache ? lock_retrieve($cache) : get_times());
    if (exists $i->{$str}) {
        $i->{$str}++;
    } else {
        $i->{$str} = scalar @defaults + 1;
    }
    lock_nstore($i, $cache);

    cancel_caffeinate() if $active_sleep;

    my $dur_h = $dur;
    my $unit_h = ($unit eq 'h' ? 'hour' : 'minute');
    $unit_h .= 's' if $dur_h != 1;

    $dur *= 60 if $unit eq 'h';
    $dur *= 60;

    # TODO: Launch caffeinate here

    return "Enabling caffeinate for $dur_h $unit_h ($dur seconds)\n";
}

sub cancel_caffeinate() {
    # TODO: Kill asserting caffeinate job that we launched
    if (not $active_sleep) {
        return "No active caffeinate jobs.\n";
    }
    return "Cancelling existing caffeinate job. ",
          "(Had $active_sleep remaining.)\n";
}

sub get_times() {
    my $t;
    if (not -f $cache) {
        my $count = scalar @defaults;
        %$t = map { $_ => $count-- } @defaults;
    } else {
        $t = lock_retrieve($cache);
    }
    return $t;
}

sub get_intervals() {
    my @items;
    my $t = get_times;
    my @times = sort { $t->{$b} <=> $t->{$a} } keys %$t;
    @times = @times[0..8] if @times > 9;

    foreach my $time (@times) {
        my ($dur, $unit) = $time =~ /(\d+)([hm])/;
        my $str = ($unit eq 'h' ? 'hour' : 'minute');
        $str .= 's' if $dur != 1;
        $str = "$dur $str";

        push(@items, {
                arg => "enable $time",
                title => "Prevent sleep for $str",
                subtitle => "Activate caffeinate for $str",
                cancellable => 1,
            });
    }
    return \@items;
}

#
# MAIN
#
chdir $FindBin::Bin or die "Failed to cd to work directory: $!\n";

$active_sleep = check_existing_caffeinate_task;

my $items = get_intervals();

my $arg = shift;
if ($arg) {
    if ($arg eq 'enable') {
        print enable_caffeinate(shift);
        exit 0;
    } elsif ($arg eq 'cancel') {
        print cancel_caffeinate;
        exit 0;
    }

    # Try to interpret argument as caffeinate duration
    my ($dur, $unit) = $arg =~ /(\d+)\s*([hm])?/i;
    if ($dur) {
        if (not $unit) {
            # Estimate based on duration
            $unit = ($dur < 10 ? 'h' : 'm');
        }
        my $unit_h = ($unit eq 'h' ? 'hour' : 'minute');
        $unit_h .= 's' if $dur != 1;
        unshift(@$items, {
                title => "Prevent sleep for $dur $unit_h",
                subtitle => "Activate caffeinate for $dur $unit_h",
                arg => "enable $dur$unit",
                cancellable => 1,
            });
    }
} elsif ($active_sleep) {
    unshift(@$items, {
            title => "Cancel existing caffeinate task",
            subtitle => "Preventing sleep for $active_sleep",
            arg => 'cancel',
        });
}

print genfeedback($items);
