#!/bin/perl
#=============================================================================
# plane-issues-updater
#=============================================================================
use strict;
use warnings;

#=============================================================================
use Getopt::Long;
use Pod::Usage;
use feature qw(say);

use Data::Dumper;

use REST::Client;
use JSON;
use HTML::TreeBuilder;

use DateTime;
use DateTime::Event::ICal;
use DateTime::Format::Strptime;

#=============================================================================
=head1 NAME

plane-issues-updater.pl

=head1 VERSION

0.1

=head1 SYNOPSIS

plane-issues-updater.pl -u <url> [options]

A Perl script for updating 'recurring' issues in a plane.so workspace.

    -d, -date <date>        The 'current date'. Default: today. <date> is an ISO8601 date
    -h, -help               This help text
    -k, -key <file>         File containing the API key. Default: ./secrets/api-key
    -s, -status <string>    Update issues with a status of <string>
    -u, -url <url>          plane.so base URL. See plane-issues-updater(1) for more details
    -v, -verbose            Provide verbose output
    -vv                     Provide very verbose output

=head1 DESCRIPTION

A Perl script for updating 'recurring' issues in a plane.so workspace.

Use an iCal (RFC2445) RECUR clause in the first line of an issue's description to make it recur.
At present, this script only parses a subset of iCal RECUR types (specifically, INTERVAL/BYDAY).
You can add more by editing the subroutine calculate_next_event().

I run this script with a cron job, once a week, to update my recurring tasks.  Use something like this in your crontab:
0 12    * * *   root    /path/to/plane-issues-updater.pl -u http://my.plane.so/api/v1/workspaces/my_workspace

=head1 PREREQUISITES

You will need Perl running on your system (this script was developed using Perl v5.34.0), plus the required modules above.
I just installed these with CPAN but other methods are available.

=head1 LICENSE

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.

=head1 AUTHOR

https://github.com/HeliosAnavatis

=cut

#=============================================================================
# Variable declarations
#=============================================================================
# Options variables
my $rundate = "";
my $givehelp ="";
my $apikeyfile = "secrets/api-key";
my $status_name = "";
my $baseurl = "";
my $verbose = "";
my $very_verbose = "";

#=============================================================================
sub update_issue
{
    my %args = (
      APIKEY => '',
      BASEURL => '',
      PROJECT => '',
      ISSUE => '',
      EVENT => '',
      STATUS => '',
      @_,  
    );
        
    my $client = REST::Client->new();
    $client->addHeader('X-API-Key',$args{APIKEY});
	$client->addHeader('Content-Type','application/json');#

    my $url = $args{BASEURL} . "projects/" . $args{PROJECT} . "/issues/" . $args{ISSUE} . "/";
	my $body = "{\"target_date\":\"" . $args{EVENT}->ymd . "\"";
    if ($args{STATUS} ne '') { $body = $body . ", \"state\": \"" . $args{STATUS}; }

    $body = $body . "\"}";

    if ($verbose)
    {
        say "[PATCH] " . $url;
        say "[BODY] " . $body;
    }

    $client->PATCH($url, $body);

    if ($client->responseCode() != 200) { die ("Error: Problem updating issue (" . $client->responseCode(). ") for " . $url); }

    if ($verbose)
    {
        say "[RESPONSE] " . Dumper($client->responseCode());
        say "[CONTENT] " . Dumper($client->responseContent());
    }

    return ($client->responseCode(), $client->responseContent());
}

#=============================================================================
sub calculate_next_event
{
    my %recur;

    # Split the string into parameters
    my $paramstr = $_[0];
    my $now = $_[1];
    $paramstr =~ s/^\S+\s*//;
    my @params = split /;/, $paramstr;

    #TODO: Pick up all of the RFC2445 RECUR parameters!

	# Split each parameter into key/value pairs
	foreach my $param (@params) {
		(my $key, my $value) = split /=/, $param;
		$value =~ s/"//g;
		$recur{$key} = $value;
        if ($very_verbose) { say "[RECUR] " . $key . " = " . $value; }
	}

    # Turn 'BYDAY' into an array
	my $bd = lc $recur{'BYDAY'};
	my @byday = ();
	if ($bd =~ /,/)	{ @byday = split /,/, $bd; }
	else { push @byday,$bd;	}

	# Create a new DateTime recur event based on the recurrence of this event
    my $set = DateTime::Event::ICal->recur(
		dtstart => $now,
		freq => lc $recur{'FREQ'},
		byday => \@byday,
		interval => $recur{'INTERVAL'}
	);

    if ($very_verbose)
    {
        say "[Recur Event Start]";
        print Dumper ($set);
        say "[Recur Event End]";
    }

	# Calculate the next ocurrence
	return $set->next($now);
}

#=============================================================================
sub get_element_details
{
    my %args = (
      APIKEY => '',
      BASEURL => '',
      PROJECT => '',
      TYPE => '',
      TYPE_ID => '',
      @_,  
    );

    my $client = REST::Client->new();
    $client->addHeader('X-API-Key',$args{APIKEY});

    my $url = $args{BASEURL} . "projects/";
    if ($args{PROJECT})
        { $url = $url. $args{PROJECT} . "/" . $args{TYPE} . "/" . $args{TYPE_ID} . "/"; }

    if ($verbose) { say $url; }

    $client->GET($url);

    if ($client->responseCode() != 200) { die ("Error: Cannot get element details (" . $client->responseCode(). ") for " . $url); }

    my $content = from_json($client->responseContent());
    return $content;
}

#=============================================================================
sub get_state_id
{
    my %args = (
      APIKEY => '',
      BASEURL => '',
      PROJECT => '',
      STATENAME => '',
      @_,  
    );

    my @elements = ();

    my $client = REST::Client->new();
    $client->addHeader('X-API-Key',$args{APIKEY});

    my $url = $args{BASEURL} . "projects/";
    if ($args{PROJECT})
        { $url = $url. $args{PROJECT} . "/states/"; }

    if ($verbose) { say "[Get State ID] " . $url; }

    $client->GET($url);    

    if ($client->responseCode() ne "200") { die ("Error: Cannot get state id (" . $client->responseCode(). ") for " . $url); }

    my $content = from_json($client->responseContent());

    if ($very_verbose)
    {
        say "[Get IDs] HTTP Response";
        print Dumper($content) . "\n";
        say "[Get IDs] End of HTTP Response";
    }
    my $details = $content->{'results'};

    for (my $i = 0; $i < $content->{'count'}; $i++)
    {
        if ($details->[$i]->{'name'} eq $args{STATENAME}) { return $details->[$i]->{'id'} }
    }

    return '';
}

#=============================================================================
# TODO: handle pagination of results with prev_cursor, next_cursor and total_pages
sub get_ids
{
    my @result = ();

    my %args = (
      APIKEY => '',
      BASEURL => '',
      PROJECT => '',
      TYPE => '',
      @_,  
    );

    my @elements = ();

    my $client = REST::Client->new();
    $client->addHeader('X-API-Key',$args{APIKEY});

    my $url = $args{BASEURL} . "projects/";
    if ($args{PROJECT})
        { $url = $url. $args{PROJECT} . "/" . $args{TYPE} . "/"; }

    if ($verbose) { say "[Get IDs] " . $url; }

    $client->GET($url);

    # TODO: Check HTTP Response code!
    if ($client->responseCode() != 200) { die ("Error: Cannot get element id (" . $client->responseCode(). ") for " . $url); }

    my $content = from_json($client->responseContent());

    if ($very_verbose)
    {
        say "[Get IDs] HTTP Response";
        print Dumper($content) . "\n";
        say "[Get IDs] End of HTTP Response";
    }
    my $details = $content->{'results'};

    for (my $i = 0; $i < $content->{'count'}; $i++)
    {
        push @elements, $details->[$i]->{'id'};
    }

    return @elements;
}

#-----------------------------------------------------------------------------
# Process command line parameters
#-----------------------------------------------------------------------------
my $result = GetOptions (
    'date|d=s' => \$rundate,
    'help|h|?' => \$givehelp,
    'key|k=s' => \$apikeyfile,
    'status|s=s' => \$status_name,
    'url|u=s' => \$baseurl,
    'verbose|v' => \$verbose,
    'vv' => \$very_verbose,
) or pod2usage( { -message => "Error: Invalid options"});

if ($givehelp)
{
    pod2usage(
        {
            -exitstatus => 0,
            -verbose => 1,
        }
    )
}

if ($rundate)
{
    my $strp = DateTime::Format::Strptime->new (pattern => '%F');
    $rundate = strp->parse_datetime ($rundate); 
}
else
{
    $rundate = DateTime->today();
}

if (not $baseurl) { pod2usage( { -message => "Error: Base URL missing." }); }

if ($verbose)
{
    say "[get options] date: " . $rundate;
    say "[get options] key: " . $apikeyfile;
    say "[get options] status: " . $status_name;
    say "[get options] url: " . $baseurl;
}

#-----------------------------------------------------------------------------
# Get the API key
#-----------------------------------------------------------------------------
open (FH, '<', $apikeyfile) or die "Error: Cannot open API key file: " . $apikeyfile;
my $apikey = <FH>;
close FH;

if ($verbose) { say "[read api key] API Key: " . $apikey . " (REDACT THIS IF POSTING THIS OUTPUT)"; }

# Get an array of project IDs
my @projects = get_ids (APIKEY => $apikey, BASEURL => $baseurl);

# Iterate over each project
for my $project_id (@projects)
{
    if ($verbose) { say "[Start processing project] " . $project_id; }

    my $status_id = get_state_id (APIKEY => $apikey, BASEURL => $baseurl, PROJECT => $project_id, STATENAME => $status_name);
    if ($verbose) { say "[status ID] " . $status_id; }

    my @issues = get_ids (APIKEY => $apikey, BASEURL => $baseurl, PROJECT => $project_id, TYPE => "issues");

    # Iterate over each issue in this project
    for my $issue_id (@issues)
    {
        if ($verbose) { say "[Start processing issue] " . $issue_id; }

        my $issue_details = get_element_details (APIKEY => $apikey, BASEURL => $baseurl, PROJECT => $project_id, TYPE => 'issues', TYPE_ID => $issue_id);

        if ($very_verbose) { print Dumper($issue_details) . "\n"; }

        # Process this issue if the first <p> tag in description_html contains the text "RECUR"
        my $tree = HTML::TreeBuilder->new;
        $tree->parse_content ($issue_details->{'description_html'});
        my $para = ($tree->look_down(_tag => 'p'))[0];
	    my $para1 = $para->{_content}[0];
        if (defined ($para1) && ($para1 =~ m/RECUR/ ))
            {
                my $next_event = calculate_next_event ($para1, $rundate);

                if ($verbose) { say "[Next Event] " . $next_event->ymd('-'); }

                update_issue (APIKEY => $apikey, BASEURL => $baseurl, PROJECT => $project_id, ISSUE => $issue_id, EVENT => $next_event, STATUS => $status_id);
            }

        if ($verbose) { say "[End processing issue] " . $issue_id; }

        # Sleep for a second between issues to avoid API throttling
        sleep 1;
    }

    if ($verbose) { say "[End processing project] " . $project_id; }
}

if ($verbose) { say "[End of update]"; }

exit 0;
