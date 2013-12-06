#!/usr/bin/perl -w
#
# %{NAME} - Anonymous, private, and caching web proxy installer.
# Copyright (C) 2013-%{YEAR}  Brandon Perkins <bperkins@redhat.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
# USA.
#

##############################################################################
# Import some semantics into the current package from the named modules
##############################################################################
use strict;                 # Restrict unsafe constructs
use warnings;               # Control optional warnings
use File::Basename;         # Parse file paths into directory,
                            # filename and suffix.
use File::Path;             # Create or remove directory trees
use File::ReadBackwards;    # Read a file backwards by lines.
use File::Temp;             # Return name and handle of a temporary
                            # file safely
use Getopt::Long;           # Getopt::Long - Extended processing
                            # of command line options
use IO::Select;             # OO interface to the select system call
use IPC::Open3;             # Open a process for reading, writing,
                            # and error handling using open3()
use Log::Log4perl;          # Log4j implementation for Perl
use Pod::Usage;             # Pod::Usage, pod2usage() - print a
                            # usage message from embedded pod
                            # documentation
use WWW::Curl::Easy;        # WWW::Curl - Perl extension interface
                            # for libcurl

##############################################################################
# Declare constants
##############################################################################
binmode STDOUT, ":utf8";    # Output UTF-8 using the :utf8 output layer.
                            # This ensures that the output is completely
                            # UTF-8, and removes any debug warnings.

$ENV{PATH}  = "/usr/sbin:/sbin:/usr/bin:/bin";
$ENV{PAGER} = "more";                            # Keep pod2usage output happy

my $name    = "%{NAME}";                         # Name string
my $version = "%{VERSION}";                      # Version number
my $release = "%{RELEASE}";                      # Release string

my $torsocksport      = "9050";    # Second-generation onion router port
my $privoxylistenport = "8118";    # Privacy Enhancing Proxy port
my $squidhttpport     = "3128";    # HTTP web proxy caching server port

my ( $wtr, $rdr, $err, $cmd );
use Symbol 'gensym';
$err = gensym;

##############################################################################
# Specify module configuration options to be enabled
##############################################################################
# Allow single-character options to be bundled. To distinguish bundles from long
# option names, long options must be introduced with '--' and bundles with '-'.
# Do not allow '+' to start options.
Getopt::Long::Configure(qw(bundling no_getopt_compat));

##############################################################################
# Initialize variables
##############################################################################
my $DBG           = 1;    # Set debug output level:
                          #   0 -- quiet
                          #   1 -- normal
                          #   2 -- verbose
                          #   3 -- debug
my $dbgtablewidth = 47;

my @ARGVOPTS = @ARGV;     # Store original command-line arguments
my %conf;                 # Active configuration
my %confargs;             # Configuration provided by command-line

##############################################################################
# cURL options
##############################################################################
my $curloptproxy     = "127.0.0.1";
my $curloptuseragent = "$name/$version";
my $curloptverbose   = 0;

##############################################################################
# Parse command line options.  This function adheres to the POSIX syntax
# for CLI options, with GNU extensions.
##############################################################################
# Initialize GetOptions variables
my $optcnfdir = "/etc/$name";
my $optdebug;
my $optdocdir = "/usr/share/doc/$name-$version";
my $opthelp;
my $optlogdir = "/var/log/$name";
my $optman;
my $optmandir = "/usr/share/man/man8";
my $optquiet;
my $optsetup;
my $optuninst;
my $optverbose;
my $optversion;

GetOptions(
    "c=i"         => \$confargs{circuits},
    "circuits=i"  => \$confargs{circuits},
    "C=s"         => \$optcnfdir,
    "configdir=s" => \$optcnfdir,
    "d"           => \$optdebug,
    "debug"       => \$optdebug,
    "D=s"         => \$optdocdir,
    "docdir=s"    => \$optdocdir,
    "h"           => \$opthelp,
    "help"        => \$opthelp,
    "L=s"         => \$optlogdir,
    "logdir=s"    => \$optlogdir,
    "m"           => \$optman,
    "man"         => \$optman,
    "M=s"         => \$optmandir,
    "mandir=s"    => \$optmandir,
    "q"           => \$optquiet,
    "quiet"       => \$optquiet,
    "S"           => \$optsetup,
    "setup"       => \$optsetup,
    "U"           => \$optuninst,
    "uninstall"   => \$optuninst,
    "v"           => \$optverbose,
    "verbose"     => \$optverbose,
    "V"           => \$optversion,
    "version"     => \$optversion
) or pod2usage(2);

##############################################################################
# Help function
##############################################################################
pod2usage(1) if $opthelp;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $optman;

##############################################################################
# Version function
##############################################################################
if ($optversion) {
    print "$name $version ($release)\n";
    exit 0;
}

##############################################################################
# Initialize Logger
##############################################################################
my $logcnf = $optcnfdir . "/log4perl.conf";
unless ( -f "$logcnf" && -r "$logcnf" ) {
    die "Cannot read Log4perl configuration file $logcnf: $!\n";
}
unless ( -d "$optlogdir" ) {
    unless ( mkpath($optlogdir) ) {
        die "Cannot create log directory $optlogdir: $!\n";
    }
}
unless ( -d "$optlogdir" && -w "$optlogdir" ) {
    die "Cannot write to log directory $optlogdir: $!\n";
}

sub getLogDir() {
    return $optlogdir;
}

Log::Log4perl::init($logcnf);
my $logger = Log::Log4perl->get_logger();
$logger->debug( "Log4perl logger started using " . $logcnf );
$logger->debug( "GetOptions: " . join( "|", @ARGVOPTS ) );
my $installer   = $optlogdir . "/" . $name . "_install";
my $uninstaller = $optlogdir . "/" . $name . "_uninstall";
my $conffile    = $optcnfdir . "/$name.conf";

##############################################################################
# Set output level
##############################################################################
# If multiple outputs are specified, the most verbose will be used.
if ($optquiet) {
    $DBG = 0;
}
if ($optverbose) {
    $DBG = 2;
    $|   = 1;
}
if ($optdebug) {
    $DBG = 3;
    $|   = 1;
}
$logger->debug("Debug level set to $DBG");

##############################################################################
# Setup temporary directory
##############################################################################
my $tmpdir     = File::Temp->newdir();
my $tmpdirname = $tmpdir->dirname;

##############################################################################
# Determine if SELinux is enabled and enforcing
##############################################################################
$cmd = "selinuxenabled";
$logger->debug("Determining if SELinux is enabled");
&runcmd;

$cmd = "getenforce | grep -i ^enforcing\$ > /dev/null";
$logger->debug("Determining if SELinux is enforcing");
&runcmd;

##############################################################################
# SELinux port types
##############################################################################
my $torpt     = "tor_port_t";
my $privoxypt = "http_cache_port_t";
my $squidpt   = "squid_port_t";

##############################################################################
# Configuration file locations
##############################################################################
my $torcfg     = "/etc/tor/torrc";
my $privoxycfg = "/etc/privoxy/config";
my $squidcfg   = "/etc/squid/squid.conf";

##############################################################################
# Log rotate file locations
##############################################################################
my $torlrfile     = "/etc/logrotate.d/tor";
my $privoxylrfile = "/etc/logrotate.d/privoxy";
my $squidlrfile   = "/etc/logrotate.d/squid";

##############################################################################
# Data directory locations
##############################################################################
my $tordatadir     = "/var/lib/tor";
my $privoxydatadir = "";
my $squiddatadir   = "/var/spool/squid";

##############################################################################
# Log directory locations
##############################################################################
my $torlogdir     = "/var/log/tor";
my $privoxylogdir = "/var/log/privoxy";
my $squidlogdir   = "/var/log/squid";

##############################################################################
# Checking for invalid options
##############################################################################
if ( $optsetup && $optuninst ) {
    $logger->logcroak("Cannot specify setup and uninstall at the same time!");
}

##############################################################################
# Running Setup
##############################################################################
if ($optsetup) {
    $logger->info("Running $name setup...");

    $logger->info("Using configuration file $conffile");

    &readconf;
    &loadargs;
    &checkconf;
    &writeconf;

    $logger->info("Done.");
    exit 0;
}

##############################################################################
# Running Uninstaller
##############################################################################
if ($optuninst) {
    $logger->warn("Running $name uninstaller...");
    $logger->info("Using installation file $installer");
    my $bwinst;
    unless ( $bwinst = File::ReadBackwards->new($installer) ) {
        $logger->logcroak("Cannot open $installer file for reading: $?");
    }

    if ( -f $uninstaller ) {
        my (
            $dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
            $size, $atime, $mtime, $ctime, $blksize, $blocks
        ) = stat($uninstaller);
        unless ( rename( $uninstaller, "$uninstaller.$mtime" ) ) {
            $logger->logcroak(
                "Unable to rename $uninstaller as $uninstaller.$mtime");
        }
    }
    unless ( open( UNINST, ">$uninstaller" ) ) {
        $logger->logcroak("Cannot open $uninstaller file for writing: $?");
    }

    while ( defined( my $logline = $bwinst->readline ) ) {
        print ".";
        $cmd = $logline;
        if ( $cmd =~ m/^semanage port / ) {
            if ( $cmd =~ m/^semanage port -a / ) {
                $cmd =~ s/^semanage port -a /semanage port -d /g;
            }
            elsif ( $cmd =~ m/^semanage port -d / ) {
                $cmd =~ s/^semanage port -d /semanage port -a /g;
            }
            else {
                $logger->logcroak("Unknown semanage port command: $cmd");
            }
        }
        if ( $cmd =~ m/^semanage fcontext / ) {
            if ( $cmd =~ m/^semanage fcontext -a / ) {
                $cmd =~ s/^semanage fcontext -a /semanage fcontext -d /g;
            }
            elsif ( $cmd =~ m/^semanage fcontext -d / ) {
                $cmd =~ s/^semanage fcontext -d /semanage fcontext -a /g;
            }
            else {
                $logger->logcroak("Unknown semanage fcontext command: $cmd");
            }
        }
        $cmd =~ s /^systemctl enable /systemctl disable /g;
        $cmd =~ s /^systemctl start /systemctl stop /g;
        $cmd =~ s /^touch /rm /g;
        &runcmd;
        print UNINST "$cmd";
    }
    print "\n";

    close(UNINST);

    $logger->warn("Done.");
    exit 0;
}

##############################################################################
# Running Installer
##############################################################################
$logger->info("Running $name installer...");
if ( -f $installer ) {
    my (
        $dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
        $size, $atime, $mtime, $ctime, $blksize, $blocks
    ) = stat($installer);
    unless ( rename( $installer, "$installer.$mtime" ) ) {
        $logger->logcroak("Unable to rename $installer as $installer.$mtime");
    }
}
unless ( open( INST, ">$installer" ) ) {
    $logger->logcroak("Cannot open $installer file for writing: $?");
}

$logger->info("Using configuration file $conffile");

&readconf;
&loadargs;
&checkconf;
&writeconf;

##############################################################################
# cURL browser setup
##############################################################################
my $browser = WWW::Curl::Easy->new;
$browser->setopt( CURLOPT_VERBOSE, $curloptverbose );
my $curlversion = $browser->version(CURLVERSION_NOW);
chomp $curlversion;
my @curlversions = split( /\s/, $curlversion );
my %libversions;
foreach my $curlver (@curlversions) {
    my ( $lib, $ver ) = split( /\//, $curlver );
    my ( $major, $minor, $patch ) = split( /\./, $ver );
    $libversions{$lib}              = $ver;
    $libversions{ $lib . '-major' } = $major;
    $libversions{ $lib . '-minor' } = $minor;
    $libversions{ $lib . '-patch' } = $patch;
    my $title = "curl, libcurl, & 3rd party library versions";
    $title =~ tr/a-z/A-Z/;
    my $eqsgns  = ( ( $dbgtablewidth - length($title) - 2 ) / 2 );
    my $eqcount = 0;
    my $eqhr    = "";

    while ( $eqcount < $eqsgns ) {
        $eqhr = $eqhr . "=";
        $eqcount++;
    }
    my $hdr = sprintf( "%s %s %s", $eqhr, $title, $eqhr );
    $logger->debug( sprintf( "%${dbgtablewidth}.${dbgtablewidth}s\n", $hdr ) );
    my $maxmodlength = 0;
    foreach my $name ( keys %libversions ) {
        my $modlength = length($name);
        if ( $modlength > $maxmodlength ) {
            $maxmodlength = $modlength;
        }
    }
    my $modverlength = ( $dbgtablewidth - $maxmodlength - 8 );
    foreach my $name ( sort ( keys %libversions ) ) {
        my $info = $libversions{$name};
        $logger->debug(
            sprintf(
"== %${maxmodlength}.${maxmodlength}s: %-${modverlength}.${modverlength}s ==\n",
                $name, $info
            )
        ) if defined $info;
    }
}

$browser->setopt( CURLOPT_USERAGENT, $curloptuseragent );
my $retcode;

# Get SELinux port status before run
$cmd = "semanage port -E | sort > $tmpdirname/seports.before";
$logger->debug("Getting SELinux port status before run");
&runcmd;

# Get SELinux fcontext status before run
$cmd = "semanage fcontext -E | sort > $tmpdirname/sefcontexts.before";
$logger->debug("Getting SELinux fcontext status before run");
&runcmd;

my $circuit = 0;
while ( $circuit < $conf{circuits} ) {
    $circuit++;
    $logger->info("Installing circuit $circuit...");

    ##########################################################################
    # Tor Circuit installation
    ##########################################################################
    $logger->info(
        "Installing tor circuit $circuit on port $conf{'torport' . $circuit}..."
    );

    ##########################################################################
    # Tor SELinux port type modifications
    ##########################################################################
    $logger->debug(
"Setting SELinux type to $torpt on tcp protocol port $conf{'torport' . $circuit}..."
    );
    $cmd =
"semanage port -a -t $torpt -p tcp $conf{'torport' . $circuit} ; if [ \$? -ne 0 ]; then semanage port -m -t $torpt -p tcp $conf{'torport' . $circuit}; fi";
    &runcmd;

    ##########################################################################
    # Tor configuration file generation
    ##########################################################################
    $logger->debug(
        "Configuring tor daemon running on port $conf{'torport' . $circuit}..."
    );
    my $torc = $torcfg . "_" . $conf{ 'torport' . $circuit };
    $cmd = "touch $torc";
    &runcmd;
    print INST "$cmd\n";
    unless ( open( CFG, ">$torc" ) ) {
        $logger->logcroak("Unable to open $torc for writing: $!");
    }
    print CFG "SocksPort $conf{'torport' . $circuit} ";
    print CFG "# Bind to localhost:$conf{'torport' . $circuit} ";
    print CFG "for local connections.\n";
    print CFG "AllowInvalidNodes middle,rendezvous\n";
    my @loglevels = ( "debug", "info", "notice", "warn", "err" );
    foreach my $loglevel (@loglevels) {
        my $logf =
            "$torlogdir"
          . $loglevel . "_"
          . $conf{ 'torport' . $circuit } . ".log";
        print CFG "Log $loglevel file $logf\n";
        if ( $loglevel =~ m/^notice$/ ) {
            print CFG "Log $loglevel syslog\n";
        }
    }
    print CFG "RunAsDaemon 1\n";
    my $tordd = $tordatadir . "_" . $conf{ 'torport' . $circuit };
    if ( !-d $tordd ) {
        unless ( mkdir($tordd) ) {
            $logger->logcroak("Unable to create directory $tordd: $!");
        }
        $cmd = "chmod \$(stat -c %a $tordatadir) $tordd";
        &runcmd;
        $cmd = "chcon \$(stat -c %C $tordatadir) $tordd";
        &runcmd;
        $cmd = "chgrp \$(stat -c %G $tordatadir) $tordd";
        &runcmd;
        $cmd = "chown \$(stat -c %U $tordatadir) $tordd";
        &runcmd;
        $cmd =
"semanage fcontext -a -e $tordatadir $tordd ; if [ \$? -ne 0 ]; then semanage fcontext -m -e $tordatadir $tordd; fi";
        &runcmd;
        $cmd = "restorecon -R -v $tordd";
        &runcmd;
    }
    print CFG "DataDirectory $tordd\n";
    print CFG "User toranon\n";
    print CFG "PidFile $tordd/tor_" . $conf{ 'torport' . $circuit } . ".pid\n";

    close(CFG);
    $cmd = "chmod \$(stat -c %a $torcfg) $torc";
    &runcmd;
    $cmd = "chcon \$(stat -c %C $torcfg) $torc";
    &runcmd;
    $cmd = "chgrp \$(stat -c %G $torcfg) $torc";
    &runcmd;
    $cmd = "chown \$(stat -c %U $torcfg) $torc";
    &runcmd;
    $cmd =
"semanage fcontext -a -e $torcfg $torc ; if [ \$? -ne 0 ]; then semanage fcontext -m -e $torcfg $torc; fi";
    &runcmd;
    $cmd = "restorecon -R -v $torc";
    &runcmd;

    ##########################################################################
    # Tor systemd system and service management
    ##########################################################################
    $logger->debug(
        "Enabling tor daemon running on port $conf{'torport' . $circuit}...");
    $cmd = "systemctl enable tor@" . $conf{ 'torport' . $circuit } . ".service";
    &runcmd;
    print INST "$cmd\n";

    $logger->debug(
        "Starting tor daemon running on port $conf{'torport' . $circuit}...");
    $cmd = "systemctl start tor@" . $conf{ 'torport' . $circuit } . ".service";
    &runcmd;
    print INST "$cmd\n";

    ##########################################################################
    # Tor simple tests
    ##########################################################################
    $logger->info(
        "Testing tor daemon running on port $conf{'torport' . $circuit}...");

    testtor( $conf{ 'torport' . $circuit }, "socks" );

    $logger->info(
"Installation of tor circuit $circuit on port $conf{'torport' . $circuit} is complete."
    );

    ##########################################################################
    # Privoxy Circuit installation
    ##########################################################################
    $logger->info(
"Installing privoxy circuit $circuit on port $conf{'privoxyport' . $circuit}..."
    );

    ##########################################################################
    # Privoxy SELinux port type modifications
    ##########################################################################
    $logger->debug(
"Setting SELinux type to $privoxypt on tcp protocol port $conf{'privoxyport' . $circuit}..."
    );
    $cmd =
"semanage port -a -t $privoxypt -p tcp $conf{'privoxyport' . $circuit} ; if [ \$? -ne 0 ]; then semanage port -m -t $privoxypt -p tcp $conf{'privoxyport' . $circuit}; fi";
    &runcmd;

    ##########################################################################
    # Privoxy configuration file generation
    ##########################################################################
    $logger->debug(
"Configuring privoxy daemon running on port $conf{'privoxyport' . $circuit}..."
    );
    my $privoxyc = $privoxycfg . "_" . $conf{ 'privoxyport' . $circuit };
    $cmd = "touch $privoxyc";
    &runcmd;
    print INST "$cmd\n";
    unless ( open( CFG, ">$privoxyc" ) ) {
        $logger->logcroak("Unable to open $privoxyc for writing: $!");
    }

    print CFG "confdir /etc/privoxy\n";
    print CFG "logdir $privoxylogdir\n";
    print CFG "actionsfile match-all.action ";
    print CFG "# Actions that are applied to ";
    print CFG "all sites and maybe overruled later on.\n";
    print CFG "actionsfile default.action   # Main actions file\n";
    print CFG "actionsfile user.action      # User customizations\n";
    print CFG "filterfile default.filter\n";
    print CFG "filterfile user.filter      # User customizations\n";
    print CFG "logfile logfile_" . $conf{ 'privoxyport' . $circuit } . ".log\n";
    print CFG "debug     1 ";
    print CFG "# Log the destination for each request ";
    print CFG "Privoxy let through. See also debug 1024.\n";
    print CFG "debug  1024 # Actions that are applied ";
    print CFG "to all sites and maybe overruled later on.\n";
    print CFG "debug  4096 # Startup banner and warnings\n";
    print CFG "debug  8192 # Non-fatal errors\n";
    print CFG "listen-address  $curloptproxy:$conf{'privoxyport' . $circuit}\n";
    print CFG "toggle  1\n";
    print CFG "enable-remote-toggle  0\n";
    print CFG "enable-remote-http-toggle  0\n";
    print CFG "enable-edit-actions 0\n";
    print CFG "enforce-blocks 0\n";
    print CFG "buffer-limit 4096\n";
    print CFG "enable-proxy-authentication-forwarding 0\n";

    my @pps = ( "/", ":443" );
    foreach my $pp (@pps) {
        print CFG "forward-socks5t     $pp  ";
        print CFG "$curloptproxy:$conf{'torport' . $circuit}  .\n";
        print CFG "forward  192.168.*.*$pp  .      ";
        print CFG "# Private-Use  [RFC1918]\n";
        my $privsub = 16;
        while ( $privsub < 32 ) {
            print CFG "forward   172.$privsub.*.*$pp  .      ";
            print CFG "# Private-Use  [RFC1918]\n";
            $privsub++;
        }
        print CFG "forward     10.*.*.*$pp  .      ";
        print CFG "# Private-Use  [RFC1918]\n";
        print CFG "forward    127.*.*.*$pp  .      ";
        print CFG "# Loopback     [RFC1122], section 3.2.1.3\n";
        print CFG "forward    localhost$pp  .\n";
    }

    print CFG "forwarded-connect-retries  1\n";
    print CFG "accept-intercepted-requests 0\n";
    print CFG "allow-cgi-request-crunching 0\n";
    print CFG "split-large-forms 0\n";
    print CFG "keep-alive-timeout 5\n";
    print CFG "tolerate-pipelining 1\n";
    print CFG "socket-timeout 300\n";

    close(CFG);
    $cmd = "chmod \$(stat -c %a $privoxycfg) $privoxyc";
    &runcmd;
    $cmd = "chcon \$(stat -c %C $privoxycfg) $privoxyc";
    &runcmd;
    $cmd = "chgrp \$(stat -c %G $privoxycfg) $privoxyc";
    &runcmd;
    $cmd = "chown \$(stat -c %U $privoxycfg) $privoxyc";
    &runcmd;
    $cmd =
"semanage fcontext -a -e $privoxycfg $privoxyc ; if [ \$? -ne 0 ]; then semanage fcontext -m -e $privoxycfg $privoxyc; fi";
    &runcmd;
    $cmd = "restorecon -R -v $privoxyc";
    &runcmd;

    ##########################################################################
    # Privoxy systemd system and service management
    ##########################################################################
    $logger->debug(
"Enabling privoxy daemon running on port $conf{'privoxyport' . $circuit}..."
    );
    $cmd =
        "systemctl enable privoxy@"
      . $conf{ 'privoxyport' . $circuit }
      . ".service";
    &runcmd;
    print INST "$cmd\n";

    $logger->debug(
"Starting privoxy daemon running on port $conf{'privoxyport' . $circuit}..."
    );
    $cmd =
        "systemctl start privoxy@"
      . $conf{ 'privoxyport' . $circuit }
      . ".service";
    &runcmd;
    print INST "$cmd\n";

    ##########################################################################
    # Privoxy simple tests
    ##########################################################################
    $logger->info(
"Testing privoxy daemon running on port $conf{'privoxyport' . $circuit}..."
    );

    $browser->setopt( CURLOPT_PROXY,     $curloptproxy );
    $browser->setopt( CURLOPT_PROXYPORT, $conf{ 'privoxyport' . $circuit } );
    $browser->setopt( CURLOPT_PROXYTYPE, CURLPROXY_HTTP );
    my $privoxytesturi = "http://config.privoxy.org/";
    $browser->setopt( CURLOPT_URL, $privoxytesturi );
    my $orgprivoxyconfightml;
    $browser->setopt( CURLOPT_WRITEDATA, \$orgprivoxyconfightml );
    $retcode = $browser->perform;
    $logger->logcroak( "\nCannot get $privoxytesturi -- $retcode "
          . $browser->strerror($retcode) . " "
          . $browser->errbuf
          . "\n" )
      unless ( $retcode == 0 );
    $logger->logcroak(
        "\nDid not receive HTML, got -- ",
        $browser->getinfo(CURLINFO_CONTENT_TYPE)
    ) unless $browser->getinfo(CURLINFO_CONTENT_TYPE) eq 'text/html';

    $logger->trace($orgprivoxyconfightml);

    if ( $orgprivoxyconfightml =~ m/Privoxy/ ) {
        if ( $orgprivoxyconfightml =~ m/127\.0\.0\.1/ ) {
            $logger->debug("Privoxy state appears to be up.");
            if ( $orgprivoxyconfightml =~
                m/port ($conf{ 'privoxyport' . $circuit })/
                && $orgprivoxyconfightml =~ m/ enabled/ )
            {
                $logger->info("Privoxy state is up.");

                testtor( $conf{ 'privoxyport' . $circuit }, "http" );

                $logger->info("Tor via Privoxy state is up.");
            }
            elsif ( $orgprivoxyconfightml =~ m/Privoxy is not being used/ ) {
                $logger->logcroak("Privoxy state is down.");
            }
            else {
                $logger->logcroak(
                    "Cannot determine Privoxy state: $orgprivoxyconfightml");
            }
        }
        else {
            $logger->logcroak(
                "Cannot determine Privoxy state: $orgprivoxyconfightml");
        }
    }
    else {
        $logger->logcroak(
            "Cannot determine Privoxy state: $orgprivoxyconfightml");
    }

    $logger->info(
"Installation of privoxy circuit $circuit on port $conf{'privoxyport' . $circuit} is complete."
    );
}

##############################################################################
# Squid installation
##############################################################################
$logger->info("Installing squid on port $conf{'squidport'}...");

##############################################################################
# Squid SELinux port type modifications
##############################################################################
$logger->debug(
"Setting SELinux type to $squidpt on tcp protocol port $conf{'squidport'}..."
);
$cmd =
"semanage port -a -t $squidpt -p tcp $conf{'squidport'} ; if [ \$? -ne 0 ]; then semanage port -m -t $squidpt -p tcp $conf{'squidport'}; fi";
&runcmd;

##############################################################################
# Squid configuration file generation
##############################################################################
$logger->debug(
    "Configuring squid daemon running on port $conf{'squidport'}...");
my $squidc = $squidcfg . "_" . $conf{'squidport'};
$cmd = "touch $squidc";
&runcmd;
print INST "$cmd\n";
unless ( open( CFG, ">$squidc" ) ) {
    $logger->logcroak("Unable to open $squidc for writing: $!");
}

print CFG "acl localnet src 10.0.0.0/8\t";
print CFG "# RFC1918 possible internal network\n";
print CFG "acl localnet src 172.16.0.0/12\t";
print CFG "# RFC1918 possible internal network\n";
print CFG "acl localnet src 192.168.0.0/16\t";
print CFG "# RFC1918 possible internal network\n";
print CFG "acl SSL_ports port 443\n";
print CFG "acl Safe_ports port 80\t\t# http\n";
print CFG "acl Safe_ports port 21\t\t# ftp\n";
print CFG "acl Safe_ports port 443\t\t# https\n";
print CFG "acl Safe_ports port 70\t\t# gopher\n";
print CFG "acl Safe_ports port 210\t\t# wais\n";
print CFG "acl Safe_ports port 1025-65535\t# unregistered ports\n";
print CFG "acl Safe_ports port 280\t\t# http-mgmt\n";
print CFG "acl Safe_ports port 488\t\t# gss-http\n";
print CFG "acl Safe_ports port 591\t\t# filemaker\n";
print CFG "acl Safe_ports port 777\t\t# multiling http\n";
print CFG "acl CONNECT method CONNECT\n";
print CFG "http_access allow localhost manager\n";
print CFG "http_access deny manager\n";
print CFG "http_access deny !Safe_ports\n";
print CFG "http_access deny CONNECT !SSL_ports\n";
print CFG "http_access deny to_localhost\n";
print CFG "http_access allow localnet\n";
print CFG "http_access allow localhost\n";
print CFG "http_access deny all\n";
print CFG "icp_access deny all\n";
print CFG "htcp_access deny all\n";
print CFG "htcp_clr_access deny all\n";
print CFG "ident_lookup_access deny all\n";
print CFG "http_port $conf{'squidport'}\n";
$circuit = 0;

while ( $circuit < $conf{circuits} ) {
    $circuit++;
    print CFG "cache_peer $curloptproxy parent ";
    print CFG "$conf{'privoxyport' . $circuit} 0 ";
    print CFG "no-query round-robin no-digest ";
    print CFG "name=localhost-$conf{'privoxyport' . $circuit}\n";
}
print CFG "hierarchy_stoplist cgi-bin \?\n";
my $squiddd = $squiddatadir . "_" . $conf{'squidport'};
if ( !-d $squiddd ) {
    unless ( mkdir($squiddd) ) {
        $logger->logcroak("Unable to create direcsquidy $squiddd: $!");
    }
    $cmd = "chmod \$(stat -c %a $squiddatadir) $squiddd";
    &runcmd;
    $cmd = "chcon \$(stat -c %C $squiddatadir) $squiddd";
    &runcmd;
    $cmd = "chgrp \$(stat -c %G $squiddatadir) $squiddd";
    &runcmd;
    $cmd = "chown \$(stat -c %U $squiddatadir) $squiddd";
    &runcmd;
    $cmd =
"semanage fcontext -a -e $squiddatadir $squiddd ; if [ \$? -ne 0 ]; then semanage fcontext -m -e $squiddatadir $squiddd; fi";
    &runcmd;
    $cmd = "restorecon -R -v $squiddd";
    &runcmd;
}
print CFG "cache_dir ufs $squiddd 100 16 256\n";
print CFG "access_log daemon:$squidlogdir/access_"
  . $conf{'squidport'}
  . ".log squid\n";
print CFG "cache_store_log daemon:$squidlogdir/store_"
  . $conf{'squidport'}
  . ".log squid\n";
print CFG "log_mime_hdrs on\n";
print CFG "pid_filename /var/run/squid_" . $conf{'squidport'} . ".pid\n";
print CFG "cache_log $squidlogdir/cache_" . $conf{'squidport'} . ".log\n";
print CFG "coredump_dir $squiddd\n";
print CFG "refresh_pattern ^ftp:\t\t1440\t20%\t10080\n";
print CFG "refresh_pattern ^gopher:\t1440\t0%\t1440\n";
print CFG "refresh_pattern -i (/cgi-bin/|\\?) 0\t0%\t0\n";
print CFG "refresh_pattern .\t\t0\t20%\t4320\n";
print CFG "cache_effective_user squid\n";
print CFG "announce_port 0\n";
print CFG "snmp_port 0\n";
print CFG "snmp_access deny all\n";
print CFG "icp_port 0\n";
print CFG "htcp_port 0\n";
print CFG "log_icp_queries on\n";
print CFG "mcast_miss_port 0\n";
print CFG "always_direct deny all\n";
print CFG "never_direct allow all\n";
print CFG "forwarded_for delete\n";
print CFG "connect_retries 1\n";
print CFG "retry_on_error on\n";

close(CFG);
$cmd = "chmod \$(stat -c %a $squidcfg) $squidc";
&runcmd;
$cmd = "chcon \$(stat -c %C $squidcfg) $squidc";
&runcmd;
$cmd = "chgrp \$(stat -c %G $squidcfg) $squidc";
&runcmd;
$cmd = "chown \$(stat -c %U $squidcfg) $squidc";
&runcmd;
$cmd =
"semanage fcontext -a -e $squidcfg $squidc ; if [ \$? -ne 0 ]; then semanage fcontext -m -e $squidcfg $squidc; fi";
&runcmd;
$cmd = "restorecon -R -v $squidc";
&runcmd;

##############################################################################
# Squid systemd system and service management
##############################################################################
$logger->debug("Enabling squid daemon running on port $conf{'squidport'}...");
$cmd = "systemctl enable squid@" . $conf{'squidport'} . ".service";
&runcmd;
print INST "$cmd\n";

$logger->debug("Starting squid daemon running on port $conf{'squidport'}...");
$cmd = "systemctl start squid@" . $conf{'squidport'} . ".service";
&runcmd;
print INST "$cmd\n";

##############################################################################
# Squid simple tests
##############################################################################
$logger->info("Testing squid daemon running on port $conf{'squidport'}...");

$browser->setopt( CURLOPT_PROXY, "" );
my $squidtesturi =
  "http://$curloptproxy:" . $conf{'squidport'} . "/squid-internal-mgr/info";
$browser->setopt( CURLOPT_URL, $squidtesturi );
my $squidinternalmgrhtml;
$browser->setopt( CURLOPT_WRITEDATA, \$squidinternalmgrhtml );
$retcode = $browser->perform;
$logger->logcroak( "\nCannot get $squidtesturi -- $retcode "
      . $browser->strerror($retcode) . " "
      . $browser->errbuf
      . "\n" )
  unless ( $retcode == 0 );
$logger->logcroak(
    "\nDid not receive text, got -- ",
    $browser->getinfo(CURLINFO_CONTENT_TYPE)
) unless $browser->getinfo(CURLINFO_CONTENT_TYPE) eq 'text/plain';

$logger->trace($squidinternalmgrhtml);

if ( $squidinternalmgrhtml =~ m/Squid Object Cache/ ) {
    if ( $squidinternalmgrhtml =~ m/Connection information for squid/ ) {
        $logger->debug("Squid state appears to be up.");
        if (   $squidinternalmgrhtml =~ m/Cache information for squid/
            && $squidinternalmgrhtml =~ m/Memory usage for squid via mallinfo/ )
        {
            $logger->info("Squid state is up.");

            testtor( $conf{'squidport'}, "http" );

            $logger->info("Tor via Privoxy via Squid state is up.");
        }
        elsif ( $squidinternalmgrhtml =~ m/Squid is not being used/ ) {
            $logger->logcroak("Squid state is down.");
        }
        else {
            $logger->logcroak(
                "Cannot determine Squid state: $squidinternalmgrhtml");
        }
    }
    else {
        $logger->logcroak(
            "Cannot determine Squid state: $squidinternalmgrhtml");
    }
}
else {
    $logger->logcroak("Cannot determine Squid state: $squidinternalmgrhtml");
}

$logger->info("Installation of squid on port $conf{'squidport'} is complete.");

##############################################################################
# %{NAMEMIXED} systemd system and service management
##############################################################################
$logger->debug("Enabling %{NAME} target...");
$cmd = "systemctl enable %{NAME}.target";
&runcmd;
print INST "$cmd\n";

# Get SELinux port status after run
$cmd = "semanage port -E | sort > $tmpdirname/seports.after";
$logger->debug("Getting SELinux port status after run");
&runcmd;

# Get SELinux port type subtractions
$cmd =
"comm --nocheck-order -23 $tmpdirname/seports.{before,after} | sort > $tmpdirname/seports.subtracted";
$logger->debug("Getting SELinux port type subtractions");
&runcmd;

unless ( open( SEDIFF, "$tmpdirname/seports.subtracted" ) ) {
    $logger->logcroak("Cannot open $tmpdirname/seports.subtracted for reading");
}
while (<SEDIFF>) {
    $_ =~ s/^port -a /port -d /g;
    print INST "semanage $_";
}
close(SEDIFF);

# Get SELinux port type additions
$cmd =
"comm --nocheck-order -13 $tmpdirname/seports.{before,after} | sort > $tmpdirname/seports.added";
$logger->debug("Getting SELinux port type additions");
&runcmd;

unless ( open( SEDIFF, "$tmpdirname/seports.added" ) ) {
    $logger->logcroak("Cannot open $tmpdirname/seports.added for reading");
}
while (<SEDIFF>) {
    print INST "semanage $_";
}
close(SEDIFF);

close(INST);

# Get SELinux fcontext status after run
$cmd = "semanage fcontext -E | sort > $tmpdirname/sefcontexts.after";
$logger->debug("Getting SELinux fcontext status after run");
&runcmd;

# Get SELinux fcontext type subtractions
$cmd =
"comm --nocheck-order -23 $tmpdirname/sefcontexts.{before,after} | sort > $tmpdirname/sefcontexts.subtracted";
$logger->debug("Getting SELinux fcontext type subtractions");
&runcmd;

unless ( open( SEDIFF, "$tmpdirname/sefcontexts.subtracted" ) ) {
    $logger->logcroak(
        "Cannot open $tmpdirname/sefcontexts.subtracted for reading");
}
while (<SEDIFF>) {
    $_ =~ s/^fcontext -a /fcontext -d /g;
    print INST "semanage $_";
}
close(SEDIFF);

# Get SELinux fcontext type additions
$cmd =
"comm --nocheck-order -13 $tmpdirname/sefcontexts.{before,after} | sort > $tmpdirname/sefcontexts.added";
$logger->debug("Getting SELinux fcontext type additions");
&runcmd;

unless ( open( SEDIFF, "$tmpdirname/sefcontexts.added" ) ) {
    $logger->logcroak("Cannot open $tmpdirname/sefcontexts.added for reading");
}
while (<SEDIFF>) {
    print INST "semanage $_";
}
close(SEDIFF);

close(INST);

$logger->info("Done.");
exit 0;

##############################################################################
# Load all command-line arguments into hash
##############################################################################
sub loadargs {
    $logger->debug("Loading all command-line arguments into hash");
    foreach my $confkey ( keys %confargs ) {
        if ( $confargs{$confkey} ) {
            $conf{$confkey} = $confargs{$confkey};
        }
    }
}

##############################################################################
# Read all configuration file variables and values into hash
##############################################################################
sub readconf {
    $logger->debug(
        "Reading all configuration file variables and values into hash");
    if ( -f $conffile && -r $conffile ) {
        unless ( open( CONF, $conffile ) ) {
            $logger->logcroak("Cannot open $conffile for reading: $!");
        }
        while (<CONF>) {
            my ( $confkey, $confvalue ) = split( /=/, $_ );
            chomp $confvalue;
            $conf{$confkey} = $confvalue;
        }
        close(CONF);
    }
}

##############################################################################
# Write all configuration variables and values into configuration file
##############################################################################
sub writeconf {
    $logger->debug(
        "Writing all configuration variables and values into configuration file"
    );
    unless ( open( CONF, ">$conffile" ) ) {
        $logger->logcroak("Cannot open $conffile for writing: $!");
    }
    foreach my $confkey ( keys %conf ) {
        print CONF "$confkey=$conf{$confkey}\n";
    }
    close(CONF);
}

##############################################################################
# Check all configuration variables for validity
##############################################################################
sub checkconf {
    $logger->debug(
        "Checking all configuration variables and values for validity");

    $logger->debug("Checking circuits...");
    unless ( $conf{circuits} ) {
        $logger->logcroak("Number of circuits not specified!");
    }
    if ( $conf{circuits} =~ /^\d+$/ ) {
        $logger->info("      circuits: $conf{circuits}");
    }
    else {
        $logger->logcroak(
            "$conf{circuits} is not a positive integer for circuits");
    }

    my $circuit = 0;
    while ( $circuit < $conf{circuits} ) {
        $circuit++;
        $logger->debug("Checking circuit $circuit...");
        $logger->debug("Checking tor circuit $circuit...");
        unless ( $conf{ 'torport' . $circuit } ) {
            $logger->logcarp("tor port for circuit $circuit not specified");
            $conf{ 'torport' . $circuit } = $torsocksport + ( $circuit * 100 );
            $logger->warn( "Setting tor port for circuit $circuit to "
                  . $conf{ 'torport' . $circuit } );
        }
        if ( $conf{ 'torport' . $circuit } =~ /^\d+$/ ) {
            if (   $conf{ 'torport' . $circuit } > 1023
                && $conf{ 'torport' . $circuit } < 49152 )
            {
                $logger->info(
                    "    tor port $circuit: " . $conf{ 'torport' . $circuit } );
            }
            else {
                $logger->logcroak( $conf{ 'torport' . $circuit }
                      . " is not in the registered port range for tor port" );
            }
        }
        else {
            $logger->logcroak( $conf{ 'torport' . $circuit }
                  . " is not a positive integer for tor port" );
        }
        $logger->debug("Checking privoxy circuit $circuit...");
        unless ( $conf{ 'privoxyport' . $circuit } ) {
            $logger->logcarp("privoxy port for circuit $circuit not specified");
            $conf{ 'privoxyport' . $circuit } =
              $privoxylistenport + ( $circuit * 100 );
            $logger->warn( "Setting privoxy port for circuit $circuit to "
                  . $conf{ 'privoxyport' . $circuit } );
        }
        if ( $conf{ 'privoxyport' . $circuit } =~ /^\d+$/ ) {
            if (   $conf{ 'privoxyport' . $circuit } > 1023
                && $conf{ 'privoxyport' . $circuit } < 49152 )
            {
                $logger->info( "privoxy port $circuit: "
                      . $conf{ 'privoxyport' . $circuit } );
            }
            else {
                $logger->logcroak( $conf{ 'privoxyport' . $circuit }
                      . " is not in the registered port range for privoxy port"
                );
            }
        }
        else {
            $logger->logcroak( $conf{ 'privoxyport' . $circuit }
                  . " is not a positive integer for privoxy port" );
        }
    }
    $logger->debug("Checking squid...");
    unless ( $conf{'squidport'} ) {
        $logger->logcarp("squid port not specified");
        $conf{'squidport'} = $squidhttpport;
        $logger->warn( "Setting squid port to " . $conf{'squidport'} );
    }
    if ( $conf{'squidport'} =~ /^\d+$/ ) {
        if ( $conf{'squidport'} > 1023 && $conf{'squidport'} < 49152 ) {
            $logger->info( "    squid port: " . $conf{'squidport'} );
        }
        else {
            $logger->logcroak( $conf{'squidport'}
                  . " is not in the registered port range for squid port" );
        }
    }
    else {
        $logger->logcroak(
            $conf{'squidport'} . " is not a positive integer for squid port" );
    }
}

sub testtor {
    my ( $torport, $proxytype ) = @_;

    $browser->setopt( CURLOPT_PROXY, $curloptproxy );

    if ($torport) {
        if ( $torport =~ /^\d+$/ ) {
            if ( $torport > 1023 && $torport < 49152 ) {
                $logger->info("Testing Tor via $proxytype on port $torport...");
            }
            else {
                $logger->logcroak( $torport
                      . " is not in the registered port range for squid port" );
            }
        }
        else {
            $logger->logcroak(
                $torport . " is not a positive integer for squid port" );
        }

    }
    else {
        $logger->logcroak("Port not specified for Tor test");
    }
    $browser->setopt( CURLOPT_PROXYPORT, $torport );

    if ( $proxytype =~ m/socks/ ) {
        $browser->setopt( CURLOPT_PROXYTYPE, CURLPROXY_SOCKS5 );
    }
    elsif ( $proxytype =~ m/http/ ) {
        $browser->setopt( CURLOPT_PROXYTYPE, CURLPROXY_HTTP );
    }
    else {
        $logger->logcroak("$proxytype is an unknown proxy type");
    }

    my $tortesturi = "https://check.torproject.org/?lang=en_US";
    my $orgtorprojectcheckhtml;

    $browser->setopt( CURLOPT_URL,       $tortesturi );
    $browser->setopt( CURLOPT_WRITEDATA, \$orgtorprojectcheckhtml );
    $retcode = $browser->perform;
    $logger->logcroak( "\nCannot get $tortesturi -- $retcode "
          . $browser->strerror($retcode) . " "
          . $browser->errbuf
          . "\n" )
      unless ( $retcode == 0 );
    $logger->logcroak(
        "\nDid not receive HTML, got -- ",
        $browser->getinfo(CURLINFO_CONTENT_TYPE)
      )
      unless $browser->getinfo(CURLINFO_CONTENT_TYPE) eq
      'text/html; charset=utf-8';

    $logger->trace($orgtorprojectcheckhtml);

    if (   $orgtorprojectcheckhtml =~ m/tor-o/
        && $orgtorprojectcheckhtml =~ m/\.png/
        && $orgtorprojectcheckhtml =~ m/Your IP address appears to be: / )
    {
        if ( $orgtorprojectcheckhtml =~ m/tor-on\.png/ ) {
            $logger->debug("Tor state appears to be up.");
            if ( $orgtorprojectcheckhtml =~
                m/Congratulations\. This browser is configured to use Tor\./ )
            {
                $logger->info("Tor state is up.");
            }
            elsif (
                $orgtorprojectcheckhtml =~ m/Sorry\. You are not using Tor\./ )
            {
                $logger->logcroak("Tor state is down.");
            }
            else {
                $logger->logcroak(
                    "Cannot determine Tor state: $orgtorprojectcheckhtml");
            }
        }
        elsif ( $orgtorprojectcheckhtml =~ m/tor-off\.png/ ) {
            $logger->logcroak("Tor state is down.");
        }
        else {
            $logger->logcroak(
                "Cannot determine Tor state: $orgtorprojectcheckhtml");
        }
    }
    else {
        $logger->logcroak(
            "Cannot determine Tor state: $orgtorprojectcheckhtml");
    }
}

##############################################################################
# Run system calls/commands
##############################################################################
sub runcmd {
    $logger->debug("Running: $cmd");
    my $pid = open3( $wtr, $rdr, $err, $cmd );
    my $select = new IO::Select;
    $select->add( $rdr, $err );

    while ( my @ready = $select->can_read ) {
        foreach my $fh (@ready) {
            my $data;
            my $length = sysread $fh, $data, 4096;

            if ( !defined $length || $length == 0 ) {
                $logger->fatal("Error from child: $!\n")
                  unless defined $length;
                $select->remove($fh);
            }
            else {
                chomp $data;
                if ( $fh == $rdr ) {
                    $logger->warn($data);
                }
                elsif ( $fh == $err ) {
                    $logger->error($data);
                }
                else {
                    return undef;
                }
            }
        }
    }

    waitpid( $pid, 0 );
    my $child_exit_status = $? >> 8;
    if ($child_exit_status) {
        $logger->logcroak(
            "Command \"$cmd\" exited with code $child_exit_status: $!");
    }
    else {
        $logger->trace("Command \"$cmd\" exited with code $child_exit_status");
    }
}
