# plane-issues-updater

## Description
A Perl script for updating 'recurring' issues in a plane.so workspace

## Prerequisites

You will need Perl running on your system (this script was developed using Perl v5.34.0), plus the required modules in the script.
I just installed these with CPAN but other methods are available.

## How to Use

Use an iCal (RFC2445) RECUR clause in the first line of an issue's description to make it recur.
At present, this script only parses a subset of iCal RECUR types (specifically, INTERVAL/BYDAY).
You can add more by editing the subroutine calculate_next_event().

I run this script with a cron job, once a week, to update my recurring tasks.  Use something like this in your crontab:
```
0 12    * * *   root    /path/to/plane-issues-updater.pl -u http://my.plane.so/api/v1/workspaces/my_workspace
```

From the command line, use:
```
plane-issues-updater.pl -u <url> [options]
```

Options are: 
```
    -d, -date <date>        The 'current date'. Default: today. <date> is an ISO8601 date  
    -h, -help               This help text  
    -k, -key <file>         File containing the API key. Default: ./secrets/api-key  
    -s, -status <string>    Update issues with a status of <string>  
    -u, -url <url>          plane.so base URL. See plane-issues-updater(1) for more details  
    -v, -verbose            Provide verbose output  
    -vv                     Provide very verbose output
```
