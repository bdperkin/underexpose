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
use Getopt::Long;      # Getopt::Long - Extended processing
                       # of command line options
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

$ENV{PATH}  = "/usr/bin:/bin";    # Keep taint happy
$ENV{PAGER} = "more";             # Keep pod2usage output happy

my $name    = "%{NAME}";          # Name string
my $version = "%{VERSION}";       # Version number
my $release = "%{RELEASE}";       # Release string

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
    &writeconf;
    &checkconf;

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
&writeconf;
&checkconf;

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
    foreach my $confkey ( keys %conf ) {
        print "$confkey=$conf{$confkey}\n";
    }
}
