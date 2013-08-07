#!/bin/bash
# This script started out as a while loop around curl with some awk, but
#   then I had to do some more involved parsing.
# I might rewrite this in perl, but probably not since it only comes
#   every so often, and it does the job I need it to do.
# If you don't live in Santa Clara County, CA, then this script won't
#   work as-is.  You might be able to steal ideas from it though, in case
#   your court system's page is similar.
#
# Note: Be considerate to the court's site, so as to not hit it with a
#   really small sleep.  Ie. don't hit it every 5-10s.  Every couple of
#   minutes is probably enough to alert you.  It's not that the site
#   can't handle some load, but no sense having them decide they can't
#   (or won't) continue to provide status online vs. making you call or
#   report in person.
#
# -Michael Schrader

SLEEPSEC=30
RECENTMIN=30
page="http://scscourt.org/online_services/jury/jury_duty.shtml"

sleepSec=${1-$SLEEPSEC}
recentMin=${2-$RECENTMIN}
groupMatch=${3-""}
case $sleepSec in
 -h|-help|--help)   echo "Usage: $0 <sleep (sec)> <recent (min)> <groupMatch>
Def:
sleepSec    $SLEEPSEC
recentMin   $RECENTMIN
groupMatch  none

env DEBUG=-d will run with perl debug flag
"
                    exit 1
                    ;;
esac

while : ; do
    date "+[%Y/%m/%d %H:%M:%S]"
    curl -m 15 -sS $page | perl -MHTTP::Date $DEBUG -ne '
BEGIN {
    $flag = undef;
    $recent = shift;
    $groupMatch = shift || undef;
    $foundGroup = undef;
}
if (/<p>\*+ <strong>.*GROUPS[^<]+<span[^>]+>([^<]+)<\/span></) {
    $curStatus = $1;
} elsif (/<p>\*+ <strong>.*GROUPS THAT <span class="redtext">NEED TO REPORT<\/span>\s*IN PERSON\s*-\s*<span class="redtext">([^<]+)/) {
    $curStatus = "REPORT-$1";
} elsif (/(Last Updated:).+face="Arial">\s*(\S[^<]+)/) {
    my($str, $dateStr) = ($1, $2);
    my($mo, $day, $yr, $hr, $min, $ampm) = $dateStr =~ /([A-Z][a-z][a-z])[a-z]+ (\d+), (\d+) at (\d+):(\d+) (PM|AM)/;
    if ($ampm eq "PM" && $hr != 12) {
        $hr += 12;
    }
    my $convDate = str2time("$day-$mo-$yr $hr:$min");
    $diff = int((time - $convDate) / 60);
    print "$str ", brief_ts($convDate), " [$diff min old] [... $dateStr ...]\n";
    if ($diff <= $recent) {
        $flag = $diff;
    } else {
        print "\t*** Stale [$diff min old] ***\n";
    }
} else {
    if (/tr class="head">/) {
        $foundSection++;
    } elsif ($foundSection && /tr class="bgWhite"/) {
        $foundGroups++;
        $groups{$curStatus}++;
    } elsif ($foundGroups) {
        if (/td class="one"\s*>([^<]+)</) {
            $groupStr = $1;
            if (defined $groupMatch && $groupMatch && $groupStr =~ /(\d+)\s+thru\s+(\d+)/) {
                my($start, $end) = ($1, $2);
                if (grep /^$groupMatch$/, ($start .. $end)) {
                    $groupStr .= " [$groupMatch]";
                    $flagGroup++;
                    $groupFound++;
                }
            }
        } elsif (/td class="two"\s*>([^<]+)</) {
            unless ($groupStr =~ /nbsp/ && /nbsp/) {
                my $status = $1;
                printf("%-40s %-20s %20s%s\n", $curStatus, $groupStr, $status, ($flagGroup ? " *** " . ($curStatus =~ /REPORT/ ? "YOU MUST GO IN" : ($curStatus =~ /LATER/ ? "STILL ONCALL" : "UNKNOWN")) . " ***": ""));
            }
            $foundGroups = undef;
            $groupStr = undef;
            $flagGroup = undef;
        }
    } elsif ($foundSection && /<\/thead/ && defined $curStatus && ! exists $groups{$curStatus}) {
        printf("%-40s %-20s\n", $curStatus, "no entries");
        $foundSection = undef;
        $curStatus = undef;
        $foundGroups = undef;
    }
}

END {
    print "\n", "*" x 50, "\n\t*** RECENT: $diff minutes old ***\n", "*" x 50, "\n" if defined $flag;
    if ($groupMatch && ! $groupFound) {
        print "\n\t*** WARNING *** YOUR GROUP WAS NOT FOUND ***\n";
    }

    unless (defined $diff) {
        print "\n\t*** ERROR *** Could not calculate last updated entry.  Possible page error ***\n";
    }
}

sub brief_ts {
    my $ts = shift || time;
    my($sec, $min, $hr, $day, $mo, $yr) = localtime($ts);
    return(sprintf("%4d/%02d/%02d %02d:%02d:%02d", $yr+1900, $mo+1, $day, $hr, $min, $sec));
}
' $recentMin $groupMatch
    echo;
    echo "sleeping $sleepSec..."
    sleep $sleepSec;
done
