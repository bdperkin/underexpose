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

################################################################################
# Import some semantics into the current package from the named modules
################################################################################
use strict;            # Restrict unsafe constructs
use warnings;          # Control optional warnings
use File::Basename;    # Parse file paths into directory,
                       # filename and suffix.
use File::Path;        # Create or remove directory trees
use File::Temp;        # Return name and handle of a temporary file safely
use Getopt::Long;      # Getopt::Long - Extended processing
                       # of command line options
use IO::Select;        # OO interface to the select system call
use IPC::Open3;        # Open a process for reading, writing, and error
                       # handling using open3()
use Log::Log4perl;     # Log4j implementation for Perl
use Pod::Usage;        # Pod::Usage, pod2usage() - print a
                       # usage message from embedded pod
                       # documentation

################################################################################
# Declare constants
################################################################################
binmode STDOUT, ":utf8";    # Output UTF-8 using the :utf8 output layer.
                            # This ensures that the output is completely
                            # UTF-8, and removes any debug warnings.

$ENV{PATH}  = "/usr/sbin:/sbin:/usr/bin:/bin";
$ENV{PAGER} = "more";             # Keep pod2usage output happy

my $name    = "%{NAME}";          # Name string
my $version = "%{VERSION}";       # Version number
my $release = "%{RELEASE}";       # Release string

my $torsocksport = "9050";        # Second-generation onion router port
my $privoxylistenport = "8118";   # Privacy Enhancing Proxy port
my $squidhttpport = "3128";       # HTTP web proxy caching server port

my ( $wtr, $rdr, $err, $cmd );
use Symbol 'gensym';
$err = gensym;

################################################################################
# Specify module configuration options to be enabled
################################################################################
# Allow single-character options to be bundled. To distinguish bundles from long
# option names, long options must be introduced with '--' and bundles with '-'.
# Do not allow '+' to start options.
Getopt::Long::Configure(qw(bundling no_getopt_compat));

################################################################################
# Initialize variables
################################################################################
my $DBG = 1;    # Set debug output level:
                #   0 -- quiet
                #   1 -- normal
                #   2 -- verbose
                #   3 -- debug

my @ARGVOPTS = @ARGV;    # Store original command-line arguments
my %conf;                # Active configuration
my %confargs;            # Configuration provided by command-line

################################################################################
# Parse command line options.  This function adheres to the POSIX syntax for CLI
# options, with GNU extensions.
################################################################################
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

################################################################################
# Help function
################################################################################
pod2usage(1) if $opthelp;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $optman;

################################################################################
# Version function
################################################################################
if ($optversion) {
    print "$name $version ($release)\n";
    exit 0;
}

################################################################################
# Initialize Logger
################################################################################
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

################################################################################
# Set output level
################################################################################
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

################################################################################
# Setup temporary directory
################################################################################
my $tmpdir = File::Temp->newdir();
my $tmpdirname = $tmpdir->dirname;

################################################################################
# Determine if SELinux is enabled and enforcing
################################################################################
$cmd = "selinuxenabled";
$logger->debug("Determining if SELinux is enabled");
&runcmd;

$cmd = "getenforce | grep -i ^enforcing\$";
$logger->debug("Determining if SELinux is enforcing");
&runcmd;

################################################################################
# SELinux port types
################################################################################
my $torpt = "tor_port_t";
my $privoxypt = "http_cache_port_t";
my $squidpt = "squid_port_t";

################################################################################
# Checking for invalid options
################################################################################
if ( $optsetup && $optuninst ) {
    $logger->logcroak("Cannot specify setup and uninstall at the same time!");
}

################################################################################
# Running Setup
################################################################################
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

################################################################################
# Running Uninstaller
################################################################################
if ($optuninst) {
    $logger->warn("Running $name uninstaller...");
    $logger->info("Using installation file $installer");
    unless ( open( INST, "$installer" ) ) {
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

    close(UNINST);

    close(INST);
    $logger->warn("Done.");
    exit 0;
}

################################################################################
# Running Installer
################################################################################
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

# Get SELinux port status before run
$cmd = "semanage port -E | tee $tmpdirname/seports.before";
$logger->debug("Getting SELinux port status before run");
&runcmd;

my $circuit = 0;
while($circuit < $conf{circuits}) {
    $circuit++;
    $logger->info("Installing curcuit $circuit...");
    $logger->info("Installing tor circuit $circuit on port $conf{'torport' . $circuit}...");
    $logger->debug("Setting SELinux type to $torpt on tcp protocol port $conf{'torport' . $circuit}...");
    $cmd = "semanage port -a -t $torpt -p tcp $conf{'torport' . $circuit} ; if [ \$? -ne 0 ]; then semanage port -m -t $torpt -p tcp $conf{'torport' . $circuit}; fi";
    &runcmd;
    $logger->info("Installation of tor circuit $circuit on port $conf{'torport' . $circuit} is complete.");
    $logger->info("Installation of curcuit $circuit is complete.");
    
}

# Get SELinux port status after run
$cmd = "semanage port -E | tee $tmpdirname/seports.after";
$logger->debug("Getting SELinux port status after run");
&runcmd;

# Get SELinux port status change
$cmd = "comm -13 $tmpdirname/seports.{before,after} | tee $tmpdirname/seports.added";
$logger->debug("Getting SELinux port type additions");
&runcmd;

unless(open(SEDIFF, "$tmpdirname/seports.added")) {
    $logger->logcroak("Cannot open $tmpdirname/seports.added for reading");
}
while (<SEDIFF>) {
    print INST "semanage $_";
}
close(SEDIFF);

# Get SELinux port status change
$cmd = "comm -13 $tmpdirname/seports.{before,after} | tee $tmpdirname/seports.subtracted";
$logger->debug("Getting SELinux port type subtractions");
&runcmd;

unless(open(SEDIFF, "$tmpdirname/seports.added")) {
    $logger->logcroak("Cannot open $tmpdirname/seports.added for reading");
}
while (<SEDIFF>) {
    $_ =~ s/^port -a /port -d /g;
    print INST "semanage $_";
}
close(SEDIFF);

close(INST);
$logger->info("Done.");
exit 0;

################################################################################
# Load all command-line arguments into hash
################################################################################
sub loadargs {
    $logger->debug("Loading all command-line arguments into hash");
    foreach my $confkey ( keys %confargs ) {
        if ( $confargs{$confkey} ) {
            $conf{$confkey} = $confargs{$confkey};
        }
    }
}

################################################################################
# Read all configuration file variables and values into hash
################################################################################
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

################################################################################
# Write all configuration variables and values into configuration file
################################################################################
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

################################################################################
# Check all configuration variables for validity
################################################################################
sub checkconf {
    $logger->debug(
        "Checking all configuration variables and values for validity");

    $logger->debug("Checking circuits...");
    unless($conf{circuits}) {
	$logger->logcroak("Number of circuits not specified!");
    }
    if($conf{circuits} =~ /^\d+$/) {
	$logger->info("      circuits: $conf{circuits}");
    } else {
	$logger->logcroak("$conf{circuits} is not a positive integer for circuits");
    }

    my $circuit = 0;
    while($circuit < $conf{circuits}) {
	$circuit++;
	$logger->debug("Checking curcuit $circuit...");
	$logger->debug("Checking tor circuit $circuit...");
	unless($conf{'torport' . $circuit}) {
	    $logger->logcarp("tor port for circuit $circuit not specified");
	    $conf{'torport' . $circuit} = $torsocksport + ( $circuit * 100 );
	    $logger->warn("Setting tor port for circuit $circuit to " . $conf{'torport' . $circuit});
	}
	if( $conf{'torport' . $circuit} =~ /^\d+$/) {
	    if( $conf{'torport' . $circuit} > 1023 && $conf{'torport' . $circuit} < 49152 ) {
		$logger->info( "    tor port $circuit: " . $conf{'torport' . $circuit});
	    } else {
		$logger->logcroak($conf{'torport' . $circuit} . " is not in the registered port range for tor port");
	    }
	} else {
	    $logger->logcroak($conf{'torport' . $circuit} . " is not a positive integer for tor port");
	}
	$logger->debug("Checking privoxy circuit $circuit...");
	unless($conf{'privoxyport' . $circuit}) {
	    $logger->logcarp("privoxy port for circuit $circuit not specified");
	    $conf{'privoxyport' . $circuit} = $privoxylistenport + ( $circuit * 100 );
	    $logger->warn("Setting privoxy port for circuit $circuit to " . $conf{'privoxyport' . $circuit});
	}
	if( $conf{'privoxyport' . $circuit} =~ /^\d+$/) {
	    if( $conf{'privoxyport' . $circuit} > 1023 && $conf{'privoxyport' . $circuit} < 49152 ) {
		$logger->info( "privoxy port $circuit: " . $conf{'privoxyport' . $circuit});
	    } else {
		$logger->logcroak($conf{'privoxyport' . $circuit} . " is not in the registered port range for privoxy port");
	    }
	} else {
	    $logger->logcroak($conf{'privoxyport' . $circuit} . " is not a positive integer for privoxy port");
	}
    }
    $logger->debug("Checking squid...");
    unless($conf{'squidport'}) {
	$logger->logcarp("squid port not specified");
	$conf{'squidport'} = $squidhttpport;
	$logger->warn("Setting squid port to " . $conf{'squidport'});
    }
    if( $conf{'squidport'} =~ /^\d+$/) {
	if( $conf{'squidport'} > 1023 && $conf{'squidport'} < 49152 ) {
	    $logger->info( "    squid port: " . $conf{'squidport'});
	} else {
	    $logger->logcroak($conf{'squidport'} . " is not in the registered port range for squid port");
	}
    } else {
	$logger->logcroak($conf{'squidport'} . " is not a positive integer for squid port");
    }
}


################################################################################
# Run system calls/commands
################################################################################
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
	    "Command \"$cmd\" exited with code $child_exit_status: $!"
	    );
    } else {
	$logger->trace("Command \"$cmd\" exited with code $child_exit_status");
    }
}
