#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin;
use Storable qw( lock_nstore lock_retrieve );

eval {
    require Time::Duration;
    *duration = \&Time::Duration::duration;
};
if ($@) {
    require Time::Seconds;
    *duration = sub { my $t = Time::Seconds->new($_[0]); return $t->pretty; };
}

my $CAFFEINATE_FLAGS = '-is';

my $conffile = $ENV{HOME} . '/.alfred-caffeinate.conf';
my %config = ();
my $active_sleep = 0;
my $caffeine_pid = 0;
my $cache = 'intervals.cache';
my $default_icon = 'coffee.png';
my $cancel_icon = 'decaf.png';
my $pidfile = 'coffee.pid';
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
        my $icon = $item->{icon} || $default_icon;

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
        <icon>$icon</icon>
    </item>
ITEM
    }

    $xml .= <<FOOT;
</items>
FOOT

    return $xml;
}

sub create_conf() {
    if (! -f $conffile) {
        if (not open(CONF, '>', $conffile)) {
            print "Error creating config file: $conffile\n";
            exit 2;
        }
        print CONF <<EOF;
##                                    ##
## ALFRED-CAFFEINATE.CONF:VERSION=1.0 ##
##                                    ##

# Default "caffeinate" flags: $CAFFEINATE_FLAGS

# Uncomment the following line to prevent display sleep too
#CAFFEINATE_FLAGS=-ids

# Or choose your own flags. Have a look at the 'caffeinate' manual page
# for the list of valid options.
EOF
        close CONF;
    }

    print "Config file: $conffile .  \nEdit this file to configure ",
          "the workflow\n";
    system("open -a /Applications/TextEdit.app $conffile");
}

sub load_conf() {
    return if not -f $conffile;
    open(CONF, $conffile) or return;
    while (<CONF>) {
        next if not /^\s*(\w+?)\s*=\s*(.+?)\s*$/;
        $config{$1} = $2;
    }
    close CONF;
}

sub get_caffeinate_pid() {
    return 0 if not -f $pidfile;
    if (not open(PIDFILE, $pidfile)) {
        unlink $pidfile;
        return 0;
    }
    chomp (my $pid = <PIDFILE>);
    close PIDFILE;

    if ($pid and $pid =~ /^\d+$/) {
        return $pid;
    }
    return 0;
}

sub get_timeout($) {
    my $pid = shift;
    open(PMSET, "pmset -g assertions |") or die "Unable to run pmset";
    my $timeout = -1;
    while (<PMSET>) {
        next if not /^\s*pid $pid\(caffeinate\):/;
        <PMSET>; <PMSET>;
        if (<PMSET> =~ /Timeout will fire in (\d+) secs/) {
            $timeout = $1;
        }
        last;
    }
    close PMSET;
    if ($timeout < 0) {
        # Invalid pidfile
        unlink $pidfile;
    }
    return $timeout;
}

sub check_existing_caffeinate_task() {
    my $pid = get_caffeinate_pid;
    return 0 if not $pid;

    my $timeout = get_timeout($pid);
    return 0 if $timeout < 0;

    return ($pid, duration($timeout) . ' more');
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

    my $pid = fork();
    if ($pid == 0) {
        # Child
        close STDIN;
        close STDOUT;
        close STDERR;
        my @flags = split(' ', $CAFFEINATE_FLAGS);
        exec ('/usr/bin/caffeinate', @flags, '-t', $dur);
    }
    open(PIDFILE, '>', $pidfile) or die "Unable to write to file: $pidfile";
    print PIDFILE "$pid\n";
    close PIDFILE;

    return "Enabling caffeinate for $dur_h $unit_h\n";
}

sub cancel_caffeinate() {
    if (not $active_sleep) {
        return "No active caffeinate jobs.\n";
    }
    if (kill('TERM', $caffeine_pid)) {
        unlink $pidfile;
    }
    return "Cancelled existing caffeinate job. ",
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

load_conf;
$CAFFEINATE_FLAGS = $config{CAFFEINATE_FLAGS}
    if exists $config{CAFFEINATE_FLAGS};

($caffeine_pid, $active_sleep) = check_existing_caffeinate_task;

my $items = get_intervals();

my $arg = shift;
$arg =~ s/^\s*//;
$arg =~ s/\s*$//;

if ($arg) {
    if ($arg eq 'enable') {
        print enable_caffeinate(shift);
        exit 0;
    } elsif ($arg eq 'cancel') {
        print cancel_caffeinate;
        exit 0;
    } elsif ($arg =~ /^conf/) {
        print genfeedback([{
                title => 'Configure the workflow',
                subtitle => "Open config file: $conffile",
                arg => '--do-configure',
            }]);
        exit 0;
    } elsif ($arg eq '--do-configure') {
        print create_conf;
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
            subtitle => "Currently preventing sleep for $active_sleep",
            arg => 'cancel',
            icon => $cancel_icon,
        });
}

print genfeedback($items);
