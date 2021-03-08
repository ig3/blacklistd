# blacklistd

Blacklistd is a Perl script that listens for output
from [logsurfer](https://github.com/k3/logsurfer)
and maintains [nftables](https://www.nftables.org/)
blacklist and whitelist.

This repository contains the blacklistd Perl script,
a slightly modified version of logsurfer (modifiecations
are available from [ig3/logsufer](https://github.com/ig3/logsurfer)),
a few logsurfer configurations and systemd service files to run
blacklistd and the logsurfer instances.

## Prerequisites

### logsurfer
If logsurfer isn't available as a package on your distribution, you can
easily build it from [source](https://github.com/k3/logsurfer). For some
minor enhancements you may find helpful, you can build from
[this fork](https://github.com/ig3/logsurfer).

### nftables
See [nftables from distributions](https://wiki.nftables.org/wiki-nftables/index.php/Nftables_from_distributions) 
if you want to install it from a package.

See [building and installing nftables from source](https://wiki.nftables.org/wiki-nftables/index.php/Building_and_installing_nftables_from_sources)
if you want to build it from source.

### Perl
The package from your distribution will suffice.

#### Config::INI::Reader
$ sudo cpan install Config::INI::Reader

## Installation

Clone this repository and run the install script.

This will install most of the script and configuration to /usr/local/bin and
/usr/local/etc. Systemd service files are installed to /etc/systemd/system.

In nftables.conf, add a set for the blacklist:

```
    set blacklist {
        type ipv4_addr
        # The interval flag allows network addresses (e.g. 192.168.0.0/24) in the set
        flags interval
    }
```

At an appropriate point in you input chain, add the blacklist:

```
        ip saddr @blacklist counter name dropped drop
```

And include the blacklist itself:

```
include "/usr/local/etc/nftables.d/*.nft"
```

A rudimentary configuration might look like:

```
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    counter dropped {
      packets 0 bytes 0
    }
    set blacklist {
        type ipv4_addr
        # The interval flag allows network addresses (e.g. 192.168.0.0/24) in the set
        flags interval
    }
    set whitelist {
        type ipv4_addr
        # The interval flag allows network addresses (e.g. 192.168.0.0/24) in the set
        flags interval
    }
    chain LOG_DROP {
        log prefix "iptables LOG_DROP: " level debug
        drop
    }
    chain LOG_ACCEPT {
        log prefix "iptables LOG_ACCEPT: " level debug
        accept
    }
    chain input {
        type filter hook input priority 0;
        ct state related,established accept
        iifname "lo" accept
        meta l4proto tcp ip saddr 192.168.1.0/24 tcp dport 22 accept
        ip saddr @blacklist counter name dropped drop
        meta l4proto tcp tcp dport 22 jump LOG_ACCEPT
        meta l4proto tcp tcp dport 443 jump LOG_ACCEPT
        limit rate 5/minute log prefix "iptables denied: " level debug
        drop
    }
    chain forward {
        type filter hook forward priority 0;
    }
    chain output {
        type filter hook output priority 0;
    }
}

include "/usr/local/etc/nftables.d/*.nft"
```

Review and modify the syslogd services as appropriate to your system:

 * logsurfer_auth.service
 * logsurfer_blacklistd.service
 * logsurfer_mail.service
 * logsurfer_nginx.service
 * nftables.service

In particular, you may prefer to continue with your system default nftables
service. The one here runs nftables with configuration in
/usr/local/etc/nftables, and additional configurations (the blacklist) in
/usr/local/etc/nftables.d/blacklist.nft (by way of an include in
/usr/local/etc/nftables.conf).

Configurations for logsurfer are in /usr/local/etc/logsurfer.

Configuration for blacklistd is /usr/local/etc/blacklist/blacklistd.conf

The whitelist and FIFO are in /usr/local/data/blacklist.

## Motivation

Years ago, Internet connected servers I managed began to be subject to
intrusion attempts on all their exposed services. I configured firewall with
some publicly available blacklists but still they were under constant
attack. I wanted something that would add IP addresses to the blacklist
based on local logs.

I reviewed open source packages available at the time and ultimately decided
to implement this system based on logsurfer, which I had used for many
years, on many systems, for log scanning and alerting.

I ran fail2ban for a while but was frustrated by limited documentation
making it difficult to achieve the configurations I wanted. You should
consider it but for me, logsurfer was easier to work with.

## Features

Intrusion detection is done by logsurfer scanning log files.

Logsurfer allows implementation of complex correlations but the provided
configurations are simple. 

The blacklist and whitelist are maintained by a simple Perl script that
reads from a named pipe / FIFO for text inputs from logsurfer. These have
the form 'list address note' where list is one of blacklist or whitelist,
address is a single IP address and note is arbitrary text to be logged,
describing why the address was added.

Bans are permanent and immediate. A failed login attempt, failed access to
SMTP server or web server results in an immediate, permanent blacklist of
the IP address, unless the IP is already in the whitelist.

A successful SSH authentication adds an address to the whitelist.

Addresses may be added to the blacklist or whitelist manually. The blacklist
is an nftables configuration file. The whitelist is a simple text file. Each
line adds one IP address to the whitelist, with the form 'address comment',
where address is the IP address and comment is arbitrary text.

Addresses in the whitelist, local host address range (127.0/16) and common
local network (192.168/16) will not be added to the blacklist. To change the
latter exclusions, you will have to edit the Perl script itself.

## Description

One instance of logsurfer is run for each log file to be scanned. Each has
its own configuration file, with patterns (regular expressions) to identify
addresses to be added to the blacklist or a separately maintained whitelist.
These patterns are very simple - matching single lines, at the moment.

The whitelist isn't referenced in iptables but an address on the whitelist
will never be added to the blacklist. Addresses from trusted networks from
which access is required should be added to whitelist. This will happen
automatically after successful ssh login or SENDING email.

Current configuration / scanning rules are from a system running
Armbian as a server hosting websites, git and npm repositories and providing
email service, accessible via ssh (headless server). There is configuration
for scanning auth.log, mail.log and nginx/access.log. It is just a start.


## Why logsurfer

It is a familiar old tool that works well.

Any log scanner could be used. All that is required is to write commands to
the blacklistd named pipe / FIFO with the form 'list address comment',
where list is blacklist or whitelist and address is the IP address to be
added. The comment is logged but is otherwise ignored.

Logsurfer is modified to work on modern Debian:

 * Added a missing function declaration
 * Add -D option to install, to create missing directories
 * Reopen logfile if it becomes smaller

My log syslog/log roller truncates log files rather than creating new files.
Logsurfer did not detect this truncation, but it was easy to add detection
of file size becoming smaller. 

Otherwise and in particular the rule processing is all standard logsurfer.

## Why nftables

I used iptables until I had a problem with it and on investigation found that
[iptables is deprecated in debian](https://packages.debian.org/buster/iptables).
So, I took their advice and switched to using nftables. 

## Why Perl

Because it is stable, familiar and adequate to the task. The script is
simple. It is just text processing (a Perl forte). I might reimplement it in
JavaScript on Node.


## Logging

The blacklistd script logs to syslog facility local0. 

## TODO

Configuration needs to be refactored. Currently, it is in both
/usr/local/etc and /etc, which is silly.

