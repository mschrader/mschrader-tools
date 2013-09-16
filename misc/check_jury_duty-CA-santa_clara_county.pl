#!/usr/bin/perl -w
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
$|=1;
use strict;
use Getopt::Long;
use HTTP::Date;
use LWP::Simple;

my %opts = (
    'sleepSec'  => 300,
    'recentMin' => 30,
    'url'       => "http://scscourt.org/online_services/jury/jury_duty.shtml",
    'timeout'   => 15,
);

my $ret = GetOptions(\%opts, qw(help|h
                                sleepSec|s=i
                                recentMin|r=i
                                url|page|p|u=s
                                groupMatch|g=s
                                maxRuns|mr=i
                                timeout|t=i
                                )
                        );

usage() if ! $ret || $opts{help};
my $timedOut = 0;

$SIG{'ALRM'} = sub {
    warn("Timeout after $opts{timeout} seconds.\n");
    $timedOut++;
};

my $curRuns = 0;
while (1) {
    $curRuns++;
    $timedOut = 0;
    last if exists $opts{maxRuns} && defined $opts{maxRuns} && $curRuns > $opts{maxRuns};
    print "Current Time: ", brief_ts(), "\n";

    alarm($opts{timeout});
    my $content;
    eval {
        $content = get($opts{url});
        # to debug html so you don't have to fetch it over and over...
        # $content = `cat /tmp/newSrc.html`;
    };
    alarm(0);
    if ($@ || $timedOut) {
        print "\nSleeping $opts{sleepSec}\n";
        sleep $opts{sleepSec};
        last;
    }

    my($diff, $flag, $curStatus, $foundGroups, $flagGroup, $foundSection, $groupFound, $groupStr);
    my %groups = ();
    if (defined $content && length($content) > 1024) {
        foreach (split /\n/, $content) {
            print "";
        #<p><b><font size="2" face="Arial" color="red">Last Updated:</font></b><font size="2" face="Arial"> August 02, 2013 at 04:34 PM</font></p>
        #<p>**** <strong>GROUPS THAT NEED TO <span class="redtext">CHECK BACK LATER</span></strong> ****</p>
        #<p>**** <strong>GROUPS THAT <span class="redtext">NEED TO REPORT</span> IN PERSON - <span class="redtext">DTS</span></strong> **** <br />
        #<p>**** <strong>GROUPS THAT <span class="redtext">NEED TO REPORT</span> IN PERSON - <span class="redtext">HOJ</span></strong> ****<br />
        #<p>**** <strong>GROUPS THAT <span class="redtext">NEED TO REPORT</span> IN PERSON - <span class="redtext">Palo Alto</span></strong> ****<br />
        #<p>**** <strong>GROUPS THAT <span class="redtext">NEED TO REPORT</span> IN PERSON - <span class="redtext">South County Morgan Hill</span></strong> **** <br />
            s/<span class="redtext">//g;
            s/<\/span>//g;
            if (/^\s*<p>\*+ <strong>GROUPS THAT NEED TO\s*([^<]+)<\/strong>/) {
                $curStatus = $1;
                if ($curStatus =~ /REPORT IN PERSON - (.+)$/) {
                    $curStatus = "REPORT-$1";
                }
#            #} elsif (/^\s*<p>\*+ <strong>GROUPS THAT NEED TO REPORT\s*IN PERSON\s*-\s*([^<]+)\s*<\/strong>/) {
#            #    $curStatus = "REPORT-$1";
            } elsif (/Last Updated:.+face="Arial">\s*(\S[^<]+)<\/font>/) {
                my $dateStr = $1;
                my($mo, $day, $yr, $hr, $min, $ampm) = $dateStr =~ /([A-Z][a-z][a-z])[a-z]+ (\d+), (\d+) at (\d+):(\d+) (PM|AM)/;
                if ($ampm eq "PM" && $hr != 12) {
                    $hr += 12;
                }
                my $convDate = str2time("$day-$mo-$yr $hr:$min");
                $diff = int((time - $convDate) / 60);
                print "Last Updated: ", brief_ts($convDate), " [$diff min old] [... $dateStr ...]\n";
                if ($diff <= $opts{recentMin}) {
                    $flag = $diff;
                } else {
                    print "\t*** Stale [$diff min old] ***\n";
                }
            } else {
                #<tr class="head">
                # <td class="one">Juror Group Numbers</td>
                # <td class="two" >Check Back Time</td>
                if (/tr class="head">/) {
                    $foundSection++;
                } elsif ($foundSection && /tr class="bgWhite"/) {
                    $foundGroups++;
                    $groups{$curStatus}++;
                } elsif ($foundGroups) {
                    if (/td class="one"\s*>([^<]+)</) {
                        $groupStr = $1;
                        if (defined $opts{groupMatch} && $opts{groupMatch} && $groupStr =~ /(\d+)\s+thru\s+(\d+)/) {
                            my($start, $end) = ($1, $2);
                            if (grep /^$opts{groupMatch}$/, ($start .. $end)) {
                                $groupStr .= " [$opts{groupMatch}]";
                                $flagGroup++;
                                $groupFound++;
                            }
                        }
                    } elsif (/td class="two"\s*>([^<]+)</) {
                        print "";
                        my $status = $1;
                        if (($groupStr =~ /nbsp/ && /nbsp/) || $status =~ /^\s*:\s*$/) {
                            $status = undef;
                        } else {
                            $status =~ s/^\s*//g;
                            $status =~ s/\s*$//g;
                            $status =~ s/^\.//g;
                            my $msg = "UNKNOWN";
                            if ($curStatus =~ /REPORT/) {
                                $msg = "YOU MUST GO IN";
                            } elsif ($curStatus =~ /LATER/) {
                                if ($status =~ /Thank you|You are excused/) {
                                    $msg = "YOU ARE EXCUSED";
                                } else {
                                    $msg = "STILL ONCALL";
                                }
                            }
                            printf("%-40s %-20s %-22s%s\n", $curStatus, $groupStr, $status, ($flagGroup ? " *** $msg ***" : ""));
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
        }
        print "\n", "*" x 50, "\n\t*** RECENT: $diff minutes old ***\n", "*" x 50, "\n" if defined $flag;
        if ($opts{groupMatch} && ! $groupFound) {
            print "\n\t*** WARNING *** YOUR GROUP WAS NOT FOUND ***\n";
        }

        unless (defined $diff) {
            print "\n\t*** ERROR *** Could not calculate last updated entry.  Possible page error ***\n";
        }
    } else {
        warn("Invalid data back from URL: '$opts{url}'\n");
    }

    last if exists $opts{maxRuns} && defined $opts{maxRuns} && $curRuns >= $opts{maxRuns};
    print "\nSleeping $opts{sleepSec}\n";
    sleep $opts{sleepSec};
}

sub brief_ts {
    my $ts = shift || time;
    my($sec, $min, $hr, $day, $mo, $yr) = localtime($ts);
    return(sprintf("%4d/%02d/%02d %02d:%02d:%02d", $yr+1900, $mo+1, $day, $hr, $min, $sec));
}

sub usage {
    print <<USAGE;
Usage: $0 [options]
 --help|-h\t\tHelp
 --sleepSec|-s\t\tSleep between runs (in seconds) [def: $opts{sleepSec}]
 --recentMin|-r\t\tMinutes back to consider the page 'recent' [def: $opts{recentMin}]
 --groupMatch|-g\tGroup Number to call out (regex, but is anchored in the group search)
 --maxRuns\t\tExit after given number of iterations.  [def: loops indefinitely]
 --url|--page|-[pu]\tURL for court status [def: $opts{url}]
 --timeout|-t\t\tTimeout (in seconds) for URL fetch [def: $opts{timeout}]

Notes:
o The Santa Clara County page does not currently support the HEAD method
request.  It returns a 403.  Therefore, because I can't determine the
page's mod time, I have to do a GET each time.  Using content-length (the
only useful thing they return, along with a non-NTP'd current server
time) is error-prone.  It must not play well with caches either.  I'd
reckon it's their fault for incurring unncessary traffic hits.

USAGE
    exit 1;
}
