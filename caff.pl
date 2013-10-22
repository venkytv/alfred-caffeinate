#!/usr/bin/perl -w

use strict;
use warnings;

my $CAFFEINATE_FLAGS = 'is';

my $active_sleep = 0;

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
    # TODO: Store duration ($_[0]) in frequently used interval cache

    cancel_caffeinate() if $active_sleep;

    my ($dur, $unit) = $_[0] =~ /(\d+)([hm])/;
    if (not $dur or not $unit) {
        return "ERROR enabling caffeinate\n";
    }
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

#
# MAIN
#
$active_sleep = check_existing_caffeinate_task;

# TODO: Load frequently used intervals from cache
#       Order by frequency
my $items = [
        {
            arg => 'enable 1h',
            title => 'Prevent sleep for 1 hour',
            subtitle => 'Activate caffeinate for 1 hour',
            cancellable => 1,
        },
        {
            arg => 'enable 15m',
            title => 'Prevent sleep for 15 minutes',
            subtitle => 'Activate caffeinate for 15 minutes',
            cancellable => 1,
        },
    ];

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
